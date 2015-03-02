//
//  qchan-buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch
import Foundation.NSThread

/**
  A channel that uses a queue of semaphores for scheduling.
*/

final class QBufferedChan<T>: Chan<T>
{
  private let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  private let capacity: Int
  private let mask: Int

  private var head = 0
  private var tail = 0

  private let readerQueue = SemaphoreQueue()
  private let writerQueue = SemaphoreQueue()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v |= v >> 32

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.alloc(mask+1)

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
      buffer.advancedBy(i&mask).destroy()
    }
    buffer.dealloc(mask+1)
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
    if let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    else if let ws = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(ws)
    }
    OSSpinLockUnlock(&lock)
  }

  /**
    Stop the thread on a new semaphore obtained from the SemaphorePool

    The new semaphore is enqueued to readerQueue or writerQueue, and
    will be used as a signal to resume the thread at a later time.

    :param: lock a semaphore that is currently held by the calling thread.
    :param: queue the queue to which the signal should be appended
  */

  private func wait(queue: SemaphoreQueue)
  {
    precondition(lock != 0, "Lock must be locked upon entering \(__FUNCTION__)")

    let threadLock = SemaphorePool.dequeue()
    queue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
    SemaphorePool.enqueue(threadLock)
    OSSpinLockLock(&lock)
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

    if !closed && head+capacity <= tail
    {
      let threadLock = SemaphorePool.dequeue()
      writerQueue.enqueue(threadLock)
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
      OSSpinLockLock(&lock)
      while !closed && head+capacity <= tail
      {
        writerQueue.undequeue(threadLock)
        OSSpinLockUnlock(&lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        OSSpinLockLock(&lock)
      }
      SemaphorePool.enqueue(threadLock)
    }

    if !closed
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail += 1
    }
    let sent = !closed

    if let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    else if head+capacity > tail || closed, let ws = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(ws)
    }

    OSSpinLockUnlock(&lock)
    return sent
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

    if !closed && head >= tail
    {
      let threadLock = SemaphorePool.dequeue()
      readerQueue.enqueue(threadLock)
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
      OSSpinLockLock(&lock)
      while !closed && head >= tail
      {
        readerQueue.undequeue(threadLock)
        OSSpinLockUnlock(&lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        OSSpinLockLock(&lock)
      }
      SemaphorePool.enqueue(threadLock)
    }

    if head < tail
    {
      let element = buffer.advancedBy(head&mask).move()
      head += 1

      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
      else if head < tail || closed, let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
      else if let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
      OSSpinLockUnlock(&lock)
      return nil
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(ref: Selection, newElement: T) -> Bool
  {
    precondition(lock != 0, "Lock should be locked in \(__FUNCTION__)")
    // assert(lock != 0, "Lock should be locked in \(__FUNCTION__)")

    buffer.advancedBy(tail&mask).initialize(newElement)
    tail += 1

    if let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    else if head+capacity > tail || closed, let ws = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(ws)
    }

    // The lock couldn't be released until now. In another thread. It's gross.
    OSSpinLockUnlock(&lock)
    return true
  }

  override func selectPutNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && !isFull
    {
      // unlocking the spinlock will be done by insert()
      return Selection(selectionID: selectionID)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!
    var turnstiled = false

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      while !self.closed && self.head+self.capacity <= self.tail
      {
        self.writerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == cancelSelect
        {
          return
        }
        OSSpinLockLock(&self.lock)
      }

      turnstiled = true
      if let s = semaphore.get()
      {
        if !self.closed
        {
          // unlocking the spinlock (and waking the next thread) will be done by insert()
          let selection = Selection(selectionID: selectionID)
          let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
          dispatch_set_context(s, context)
        }
        else
        { // channel is closed; signal another thread
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
          else if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
          OSSpinLockUnlock(&self.lock)
          dispatch_set_context(s, nil)
        }
        dispatch_semaphore_signal(s)
      }
      else
      {
        if let ws = self.writerQueue.dequeue()
        {
          dispatch_semaphore_signal(ws)
        }
        else if self.head < self.tail || self.closed, let rs = self.readerQueue.dequeue()
        {
          dispatch_semaphore_signal(rs)
        }
        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      if !turnstiled
      { // This needs to be async because of the horrible thread-traversing
        // lock state that eventually gets resolved by insert().
        dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
          while !OSSpinLockTry(&self.lock)
          { // A kinder, gentler way to busy-wait
            NSThread.sleepForTimeInterval(100e-9)
            if turnstiled { return }
          }
          if self.writerQueue.remove(threadLock)
          {
            dispatch_set_context(threadLock, cancelSelect)
            dispatch_semaphore_signal(threadLock)
          }
          OSSpinLockUnlock(&self.lock)
        }
      }
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if head < tail
    {
      let element = buffer.advancedBy(head&mask).move()
      head += 1

      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
      else if head < tail || closed, let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
      OSSpinLockUnlock(&lock)
      return Selection(selectionID: selectionID, selectionData: element)
    }
    else
    {
      OSSpinLockUnlock(&lock)
      return nil
    }
  }

  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)! //SemaphorePool.dequeue()
    var turnstiled = false

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      while !self.closed && self.head >= self.tail
      {
        self.readerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == cancelSelect
        {
          return
        }
        OSSpinLockLock(&self.lock)
      }

      turnstiled = true
      if let s = semaphore.get()
      {
        if self.head < self.tail
        {
          let element = self.buffer.advancedBy(self.head&self.mask).move()
          self.head += 1

          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
          else if self.head < self.tail, let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
          OSSpinLockUnlock(&self.lock)

          let selection = Selection(selectionID: selectionID, selectionData: element)
          let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
          dispatch_set_context(s, context)
        }
        else
        {
          assert(self.closed, __FUNCTION__)
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
          else if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
          OSSpinLockUnlock(&self.lock)
          dispatch_set_context(s, nil)
        }
        dispatch_semaphore_signal(s)
      }
      else
      {
        if let rs = self.readerQueue.dequeue()
        {
          dispatch_semaphore_signal(rs)
        }
        else if self.head+self.capacity > self.tail || self.closed, let ws = self.writerQueue.dequeue()
        {
          dispatch_semaphore_signal(ws)
        }
        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      if !turnstiled
      {
        OSSpinLockLock(&self.lock)
        if self.readerQueue.remove(threadLock)
        {
          dispatch_set_context(threadLock, cancelSelect)
          dispatch_semaphore_signal(threadLock)
        }
        OSSpinLockUnlock(&self.lock)
      }
    }
  }
}

/**
  A useful fake pointer for use with dispatch_set_context() in Signal closures.
*/

private let cancelSelect = UnsafeMutablePointer<Void>(bitPattern: 1)
