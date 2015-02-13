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

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    buffer.advancedBy(tail&mask).initialize(newElement)
    tail += 1

    if let w = Optional(!readerQueue.isEmpty) where w,
       let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    else if head+capacity > tail // the channel isn't full
    {
      if let w = Optional(!writerQueue.isEmpty) where w, // a writer is waiting
         let ws = writerQueue.dequeue()
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

    if closed && head >= tail
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    let element = buffer.advancedBy(head&mask).move()
    head += 1

    if let w = Optional(!writerQueue.isEmpty) where w, // a writer is waiting
       let ws = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(ws)
    }
    else if head < tail // the channel isn't empty
    {
      if let w = Optional(!readerQueue.isEmpty) where w, // a reader is waiting
         let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
    }

    OSSpinLockUnlock(&lock)

    return element
  }

  // SelectableChannelType overrides

  override func insert(ref: Selection, item: T) -> Bool
  {
    precondition(lock != 0, "Lock should be locked in \(__FUNCTION__)")
    // assert(lock != 0, "Lock should be locked in \(__FUNCTION__)")

    buffer.advancedBy(tail&mask).initialize(item)
    tail += 1

    if let w = Optional(!readerQueue.isEmpty) where w,
       let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    else if let nf = Optional(head+capacity > tail) where nf, // the channel isn't full
            let w = Optional(!writerQueue.isEmpty) where w,   // a writer is waiting
            let ws = writerQueue.dequeue()
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
      // the lock will be unlocked by insert()
      return Selection(selectionID: selectionID)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    // We can't use the SemaphorePool here, because we don't know how many times
    // the semaphore will be incremented and decremented. It will be potentially
    // be referenced from two different threads, and could end up with
    // a count of 0 or 1. There is no way to tell.
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      if !self.closed && self.head+self.capacity <= self.tail
      {
        self.writerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == abortSelect
        {
          // If threadLock was awoken from a place other than the Signal closure,
          // the next thread in line needs to be awoken.
          // We don't know whether said next thread *actually* needs to be awoken.
          // Perhaps better smarts need to exist. As a workaround, a thread that gets
          // awoken but didn't need to will un-dequeue its semaphore and go back to sleep.
          if let ws = self.writerQueue.dequeue() { dispatch_semaphore_signal(ws) }
          return
        }
        OSSpinLockLock(&self.lock)
        while !self.closed && self.head+self.capacity <= self.tail
        {
          self.writerQueue.undequeue(threadLock)
          OSSpinLockUnlock(&self.lock)
          dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
          if dispatch_get_context(threadLock) == abortSelect
          {
            if let ws = self.writerQueue.dequeue() { dispatch_semaphore_signal(ws) }
            return
          }
        }
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
        let selection = Selection(selectionID: selectionID)
        let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
        dispatch_set_context(s, context)
        dispatch_semaphore_signal(s)
      }
      else
      {
        if let e = Optional(self.head >= self.tail) where !e,   // channel isn't empty
           let w = Optional(!self.readerQueue.isEmpty) where w, // a reader is waiting
           let rs = self.readerQueue.dequeue()
        {
          dispatch_semaphore_signal(rs)
        }
        else if let f = Optional(self.head+self.capacity <= self.tail) where !f, // the channel isn't full
                let w = Optional(!self.writerQueue.isEmpty) where w,             // a writer is waiting
                let ws = self.writerQueue.dequeue()
        {
          dispatch_semaphore_signal(ws)
        }

        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && head < tail
    {
      let element = buffer.advancedBy(head&mask).move()
      head += 1
      OSSpinLockUnlock(&lock)

      if let w = Optional(!self.writerQueue.isEmpty) where w, // a writer is waiting
         let ws = self.writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
      else if let e = Optional(self.head >= self.tail) where !e,   // channel isn't empty
              let w = Optional(!self.readerQueue.isEmpty) where w, // a reader is waiting
              let rs = self.readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }

      return Selection(selectionID: selectionID, selectionData: element)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    // We can't use the SemaphorePool here, because we don't know how many times
    // the semaphore will be incremented and decremented. It will be potentially
    // be referenced from two different threads, and could end up with
    // a count of 0 or 1. There is no way to tell.
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      if !self.closed && self.head >= self.tail
      {
        self.readerQueue.enqueue(threadLock)
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
        if dispatch_get_context(threadLock) == abortSelect
        {
          // If threadLock was awoken from a place other than the Signal closure,
          // the next thread in line needs to be awoken.
          // We don't know whether said next thread *actually* needs to be awoken.
          // Perhaps better smarts need to exist. As a workaround, a thread that gets
          // awoken but didn't need to will un-dequeue its semaphore and go back to sleep.
          if let rs = self.readerQueue.dequeue() { dispatch_semaphore_signal(rs) }
          return
        }
        OSSpinLockLock(&self.lock)
        while !self.closed && self.head >= self.tail
        {
          self.readerQueue.undequeue(threadLock)
          OSSpinLockUnlock(&self.lock)
          dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
          if dispatch_get_context(threadLock) == abortSelect
          {
            if let rs = self.readerQueue.dequeue()
            {
              dispatch_semaphore_signal(rs)
            }
            return
          }
          OSSpinLockLock(&self.lock)
        }
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

        if let w = Optional(!self.writerQueue.isEmpty) where w, // a writer is waiting
           let ws = self.writerQueue.dequeue()
        {
          dispatch_semaphore_signal(ws)
        }
        else if let e = Optional(self.head >= self.tail) where !e,   // channel isn't empty
                let w = Optional(!self.readerQueue.isEmpty) where w, // a reader is waiting
                let rs = self.readerQueue.dequeue()
        {
          dispatch_semaphore_signal(rs)
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
        if let f = Optional(self.head+self.capacity <= self.tail) where !f, // channel isn't full
           let w = Optional(!self.writerQueue.isEmpty) where w, // a writer is waiting
           let ws = self.writerQueue.dequeue()
        {
          dispatch_semaphore_signal(ws)
        }
        else if let e = Optional(self.head >= self.tail) where !e,   // channel isn't empty
                let w = Optional(!self.readerQueue.isEmpty) where w, // a reader is waiting
                let rs = self.readerQueue.dequeue()
        {
          dispatch_semaphore_signal(rs)
        }

        OSSpinLockUnlock(&self.lock)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
    }
  }
}

var selectCount: Int32 = 0
