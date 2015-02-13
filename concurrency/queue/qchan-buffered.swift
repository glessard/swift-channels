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
    OSSpinLockLock(&lock)
    SemaphorePool.enqueue(threadLock)
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
      wait(lock: &lock, queue: writerQueue)
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

    while !closed && head >= tail
    {
      wait(lock: &lock, queue: readerQueue)
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
}
