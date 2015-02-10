//
//  qchan-unbuffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  An unbuffered channel that uses a queue of semaphores for scheduling.
*/

final class QUnbufferedChan<T>: Chan<T>
{
  // housekeeping variables

  private let readerQueue = SemaphoreOSQueue()
  private let writerQueue = SemaphoreOSQueue()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return true
  }

  final override var isFull: Bool
  {
    return true
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
        dispatch_set_context(rs, nil)
        dispatch_semaphore_signal(rs)
      }
      OSSpinLockLock(&lock)
    }
    if writerQueue.isEmpty == false
    {
      OSSpinLockUnlock(&lock)
      while let ws = writerQueue.dequeue()
      {
        dispatch_set_context(ws, nil)
        dispatch_semaphore_signal(ws)
      }
    }
    else
    {
      OSSpinLockUnlock(&lock)
    }
  }


  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(var newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    if let rs = readerQueue.dequeue()
    { // there is already an interested reader
      OSSpinLockUnlock(&lock)

      // attach a new copy of our data to the reader's semaphore
      let pointer = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      if pointer == nil
      { // not a normal code path.
        assert(false, __FUNCTION__)
        // dispatch_semaphore_signal(nil)
        return false
      }

      pointer.initialize(newElement)
      dispatch_semaphore_signal(rs)
      return true
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // wait for a buffer from a reader
    let threadLock = SemaphorePool.dequeue()
    // attach a pointer to our data on the stack
    dispatch_set_context(threadLock, &newElement)
    writerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = UnsafePointer<T>(dispatch_get_context(threadLock))
    if context == nil
    { // thread was awoken by close(), not a reader
      SemaphorePool.enqueue(threadLock)
      return false
    }

    assert(context == &newElement)

    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)
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
    if closed { return nil }

    OSSpinLockLock(&lock)

    if let ws = writerQueue.dequeue()
    { // data is already available
      OSSpinLockUnlock(&lock)

      let context = UnsafePointer<T>(dispatch_get_context(ws))
      if context == nil
      { // not a normal code path.
        assert(false, __FUNCTION__)
        // dispatch_semaphore_signal(nil)
        return nil
      }
      let element = context.memory
      dispatch_set_context(ws, nil)
      dispatch_semaphore_signal(ws)
      return element
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    // wait for data from a writer
    let threadLock = SemaphorePool.dequeue()
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    dispatch_set_context(threadLock, buffer)
    readerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = UnsafeMutablePointer<T>(dispatch_get_context(threadLock))
    if context == nil
    { // thread was awoken by close(), not a writer
      buffer.dealloc(1)
      SemaphorePool.enqueue(threadLock)
      return nil
    }

    assert(context == buffer)

    let element = buffer.move()
    buffer.dealloc(1)
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)
    return element
  }
}
