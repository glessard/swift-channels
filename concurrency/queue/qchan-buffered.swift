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

  // housekeeping variables

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

  // Computed property accessors

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

    // Unblock the threads waiting on our conditions.
    if readerQueue.isEmpty == false
    {
      OSSpinLockUnlock(&lock)
      while let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
      OSSpinLockLock(&lock)
    }
    if writerQueue.isEmpty == false
    {
      OSSpinLockUnlock(&lock)
      while let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
    }
    else
    {
      OSSpinLockUnlock(&lock)
    }
  }

  /**
    Stop the thread on a new semaphore obtained from the SemaphorePool

    The new semaphore is enqueued to readerQueue or writerQueue, and
    will be used as a signal to resume the thread at a later time.

    :param: lock a semaphore that is currently held by the calling thread.
    :param: queue the queue to which the signal should be appended
  */

  private func wait(inout #lock: OSSpinLock, queue: SemaphoreQueue)
  {
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

    while !closed && head+capacity <= tail
    {
      let threadLock = SemaphorePool.dequeue()
      writerQueue.enqueue(threadLock)
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
      SemaphorePool.enqueue(threadLock)
      OSSpinLockLock(&lock)
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    buffer.advancedBy(tail&mask).initialize(newElement)
    tail += 1

    if !readerQueue.isEmpty
    {
      if let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
    }

    if head+capacity < tail && !writerQueue.isEmpty
    {
      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
    }

    OSSpinLockUnlock(&lock)
    return true
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

    while !closed && head >= tail
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

    if closed && head >= tail
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    let element = buffer.advancedBy(head&mask).move()
    head += 1

    if !writerQueue.isEmpty
    {
      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
    }

    if head < tail && !readerQueue.isEmpty
    {
      if let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
    }

    OSSpinLockUnlock(&lock)

    return element
  }

  // SelectableChannelType overrides

  override func selectReadyPut(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && !isFull
    {
      let semaphore = SemaphorePool.dequeue()

      async {
        // Maybe this should be called with a real timeout and checked on return.
        // (that wouldn't be SemaphorePool compatible.)
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        let p = UnsafeMutablePointer<T>(dispatch_get_context(semaphore))
        if p == nil
        { // this isn't right
          assert(false, __FUNCTION__)
          OSSpinLockUnlock(&self.lock)
          SemaphorePool.enqueue(semaphore)
          return
        }
        self.buffer.advancedBy(self.tail&self.mask).initialize(p.move())
        self.tail += 1
        OSSpinLockUnlock(&self.lock)
        // The lock couldn't be released until now. In another thread. It's kind of gross.

        p.dealloc(1)
        dispatch_set_context(semaphore, nil)
        SemaphorePool.enqueue(semaphore)

        if !self.readerQueue.isEmpty
        {
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
        }
      }

      return Selection(selectionID: selectionID, selectionData: semaphore)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectPut(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      while !self.closed && self.head+self.capacity <= self.tail
      {
        self.writerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == abortSelect
        {
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
          return
        }
        OSSpinLockLock(&self.lock)
      }

      if self.closed
      {
        OSSpinLockUnlock(&self.lock)
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }
        return
      }

      if let s = semaphore.get()
      {
        let semaphore = SemaphorePool.dequeue()

        let selection = Selection(selectionID: selectionID, selectionData: semaphore)
        let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
        dispatch_set_context(s, context)
        dispatch_semaphore_signal(s)

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        let p = UnsafeMutablePointer<T>(dispatch_get_context(semaphore))
        if p == nil
        { // this isn't right
          assert(false, __FUNCTION__)
          OSSpinLockUnlock(&self.lock)
          SemaphorePool.enqueue(semaphore)
          return
        }
        self.buffer.advancedBy(self.tail&self.mask).initialize(p.move())
        self.tail += 1
        OSSpinLockUnlock(&self.lock)

        p.dealloc(1)
        dispatch_set_context(semaphore, nil)
        SemaphorePool.enqueue(semaphore)

        if !self.readerQueue.isEmpty
        {
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
        }

        if !self.isFull && !self.writerQueue.isEmpty
        {
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
        }
      }
      else
      {
        if !self.isFull
        {
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
        }

        if !self.isEmpty
        {
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
        }

        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
    }
  }

  override func insert(ref: Selection, item: T) -> Bool
  {
    if let s: dispatch_semaphore_t = ref.getData()
    {
      let p = UnsafeMutablePointer<T>.alloc(1)
      p.initialize(item)
      dispatch_set_context(s, p)
      dispatch_semaphore_signal(s)
      return true
    }
    return false
  }

  override func selectReadyGet(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && head < tail
    {
      let element = buffer.advancedBy(head&mask).move()
      head += 1
      OSSpinLockUnlock(&lock)

      return Selection(selectionID: selectionID, selectionData: element)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectGet(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal
  {
    // We can't use the SemaphorePool here, because we don't know how many times
    // the semaphore will be incremented and decremented. It will be potentially
    // be referenced from two different threads, and could end up with
    // a count of 0 or 1. There is no way to tell.
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      while !self.closed && self.head >= self.tail
      {
        self.readerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == abortSelect
        {
          // If readerQueue was dequeued from a place other than the Signal closure,
          // the next thread in line needs to be awoken.
          // Now, we don't know whether said next thread *actually* needs to be awoken.
          // Perhaps better smarts need to exist. As a workaround, a thread that gets
          // awoken but didn't need to will un-dequeue its semaphore and go back to sleep.
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
          // We can't be sure of threadLock semaphore's state at this point,
          // therefore we cannot enqueue it to the SemaphorePool.
          return
        }
        OSSpinLockLock(&self.lock)
      }

      if self.closed && self.head >= self.tail
      {
        OSSpinLockUnlock(&self.lock)
        if let s = semaphore.get()
        {
//          syncprint("sending nil message")
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }
        return
      }

      if let s = semaphore.get()
      {
        let element = self.buffer.advancedBy(self.head&self.mask).move()
        self.head += 1

        if !self.writerQueue.isEmpty
        { // channel isn't full; dequeue a writer if one exists
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
        }

        if self.head < self.tail
        { // channel isn't empty; dequeue a reader if one exists
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
        }

        OSSpinLockUnlock(&self.lock)

        let selection = Selection(selectionID: selectionID, selectionData: element)
        let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
        dispatch_set_context(s, context)
        dispatch_semaphore_signal(s)
        return
      }
      else
      {
        if self.head+self.capacity < self.tail
        { // channel isn't full; dequeue a writer if one exists
          if let ws = self.writerQueue.dequeue()
          {
            dispatch_semaphore_signal(ws)
          }
        }

        if self.head < self.tail
        { // channel isn't empty; dequeue a reader if one exists
          if let rs = self.readerQueue.dequeue()
          {
            dispatch_semaphore_signal(rs)
          }
        }

        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
      // We can't be sure of the semaphore's state at this point,
      // so we cannot enqueue it to the SemaphorePool.
    }
  }
}

var selectCount: Int32 = 0
