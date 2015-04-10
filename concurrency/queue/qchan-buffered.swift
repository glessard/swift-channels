//
//  qchan-buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A channel that uses a queue of semaphores for scheduling.
*/

final class QBufferedChan<T>: Chan<T>
{
  private let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  private let capacity: Int64
  private let mask: Int64

  private var head: Int64 = 0
  private var tail: Int64 = 0

  private var nextput: Int64 = 0
  private var nextget: Int64 = 0

  private let readerQueue = SuperSemaphoreQueue()
  private let writerQueue = SuperSemaphoreQueue()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : Int64(capacity)

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v |= v >> 32

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.alloc(Int(mask+1))

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  deinit
  {
    for i in head..<tail
    {
      buffer.advancedBy(Int(i&mask)).destroy()
    }
    buffer.dealloc(Int(mask+1))
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return head >= tail
  }

  final override var isFull: Bool
  {
    return head+capacity <= tail
  }

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }

  // MARK: ChannelType methods

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  override func close()
  {
    if closed { return }

    OSSpinLockLock(&lock)
    closed = true

    // Unblock waiting threads.
    signalNextReader() || signalNextWriter()
    OSSpinLockUnlock(&lock)
  }

  /**
    Stop the thread on a new semaphore obtained from the SemaphorePool

    The new semaphore is enqueued to readerQueue or writerQueue, and
    will be used as a signal to resume the thread at a later time.

    :param: lock a semaphore that is currently held by the calling thread.
    :param: queue the queue to which the signal should be appended
  */

  private func wait(queue: SuperSemaphoreQueue)
  {
    precondition(lock != 0, "Lock must be locked upon entering \(__FUNCTION__)")

    let threadLock = SemaphorePool.Obtain()
    queue.enqueue(.semaphore(threadLock))
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
    SemaphorePool.Return(threadLock)
    OSSpinLockLock(&lock)
  }

  private func signalNextReader() -> Bool
  {
    while let rss = readerQueue.dequeue()
    {
      switch rss
      {
      case .semaphore(let rs):
        dispatch_semaphore_signal(rs)
        return true

      case .selection(let c, let selection):
        if let select = c.get()
        {
          nextget += 1
          dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(select)
          return true
        }
      }
    }
    return false
  }

  private func signalNextWriter() -> Bool
  {
    while let wss = writerQueue.dequeue()
    {
      switch wss
      {
      case .semaphore(let ws):
        dispatch_semaphore_signal(ws)
        return true

      case .selection(let c, let selection):
        if let select = c.get()
        {
          nextput += 1
          dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(select)
          return true
        }
      }
    }
    return false
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    while !closed && head+capacity <= nextput
    {
      wait(writerQueue)
    }

    if !closed
    {
      nextput += 1
      buffer.advancedBy(Int(tail&mask)).initialize(newElement)
      tail += 1

      if !signalNextReader()
      {
        if head+capacity > nextput || closed { signalNextWriter() }
      }
      OSSpinLockUnlock(&lock)
      return true
    }
    else
    {
      signalNextReader() || signalNextWriter()
      OSSpinLockUnlock(&lock)
      return false
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed && head >= tail { return nil }

    OSSpinLockLock(&lock)

    while !closed && nextget >= tail
    {
      wait(readerQueue)
    }

    if nextget < tail
    {
      nextget += 1
      let element = buffer.advancedBy(Int(head&mask)).move()
      head += 1

      if !signalNextWriter()
      {
        if nextget < tail || closed { signalNextReader() }
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      signalNextWriter() || signalNextReader()
      OSSpinLockUnlock(&lock)
      return nil
    }
  }

  // MARK: SelectableChannelType methods

  override func selectPutNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && head+capacity > nextput
    {
      nextput += 1
      OSSpinLockUnlock(&lock)
      return selection
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    OSSpinLockLock(&lock)
    if !closed && head+capacity > tail
    {
      buffer.advancedBy(Int(tail&mask)).initialize(newElement)
      tail += 1

      if !signalNextReader()
      {
        if head+capacity > nextput || closed { signalNextWriter() }
      }
      OSSpinLockUnlock(&lock)
      return true
    }
    else
    {
      OSSpinLockUnlock(&lock)
      return false
    }
  }

  override func selectPut(semaphore: SemaphoreChan, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if closed
    {
      OSSpinLockUnlock(&lock)
      if let s = semaphore.get()
      {
        dispatch_semaphore_signal(s)
      }
    }
    else if head+capacity > nextput // not full
    {
      if let s = semaphore.get()
      {
        nextput += 1
        OSSpinLockUnlock(&lock)
        dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
        dispatch_semaphore_signal(s)
      }
      else
      {
        if !signalNextWriter()
        {
          if nextget < tail { signalNextReader() }
        }
        OSSpinLockUnlock(&lock)
      }
    }
    else
    {
      writerQueue.enqueue(semaphore, selection: selection)
      OSSpinLockUnlock(&lock)
    }
  }

  override func selectGetNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    if nextget < tail
    {
      nextget += 1
      OSSpinLockUnlock(&lock)
      return selection
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func extract(selection: Selection) -> T?
  {
    OSSpinLockLock(&lock)
    if head < tail
    {
      let element = buffer.advancedBy(Int(head&mask)).move()
      head += 1

      if !signalNextWriter()
      {
        if nextget < tail || closed { signalNextReader() }
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      OSSpinLockUnlock(&lock)
      return nil
    }
  }
  
  override func selectGet(semaphore: SemaphoreChan, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if nextget < tail
    {
      if let s = semaphore.get()
      {
        nextget += 1
        OSSpinLockUnlock(&lock)
        dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
        dispatch_semaphore_signal(s)
      }
      else
      {
        if !signalNextReader()
        {
          if head+capacity > nextput || closed { signalNextWriter() }
        }
        OSSpinLockUnlock(&lock)
      }
    }
    else if closed
    {
      OSSpinLockUnlock(&lock)
      if let s = semaphore.get()
      {
        dispatch_semaphore_signal(s)
      }
    }
    else
    {
      readerQueue.enqueue(semaphore, selection: selection)
      OSSpinLockUnlock(&lock)
    }
  }
}

private extension SemaphoreQueue
{
  /**
    Signal the next valid semaphore from the SemaphoreQueue.
  
    For some reason, this is cost-free as an extension, but costly as a method of QBufferedChan.
  */

  private func signalNext() -> Bool
  {
    while let s = dequeue()
    {
      dispatch_semaphore_signal(s)
      return true
    }
    return false
  }
}
