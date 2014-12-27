//
//  qchan-unbuffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a 1-element buffer.
*/

final class QUnbufferedChan<T>: Chan<T>
{
  // housekeeping variables

  private let readerQueue = ObjectQueue<dispatch_semaphore_t>()
  private let writerQueue = ObjectQueue<dispatch_semaphore_t>()

  private var mutex = OS_SPINLOCK_INIT

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

    OSSpinLockLock(&mutex)
    closed = true

    // Unblock the threads waiting on our conditions.
    if readerQueue.count > 0
    {
      while let rs = readerQueue.dequeue() { dispatch_semaphore_signal(rs) }
    }
    if writerQueue.count > 0
    {
      while let ws = writerQueue.dequeue() { dispatch_semaphore_signal(ws) }
    }
    OSSpinLockUnlock(&mutex)
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

    OSSpinLockLock(&mutex)

    if let rs = readerQueue.dequeue()
    { // there is already an interested reader
      OSSpinLockUnlock(&mutex)
      // attach a new copy of our data to the reader's semaphore
      let pointer = UnsafeMutablePointer<T>.alloc(1)
      pointer.initialize(newElement)
      dispatch_set_context(rs, pointer)
      dispatch_semaphore_signal(rs)
      return true
    }

    if closed
    {
      OSSpinLockUnlock(&mutex)
      return false
    }

    let threadLock = SemaphorePool.dequeue()
    // attach a pointer to our data on the stack
    dispatch_set_context(threadLock, &newElement)
    writerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&mutex)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken by a reader (or the channel was closed)
    let context = UnsafePointer<T>(dispatch_get_context(threadLock))
    if context != UnsafePointer.null()
    { // thread was awoken by close(), not a reader
      dispatch_set_context(threadLock, nil)
      SemaphorePool.enqueue(threadLock)
      return false
    }

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

    OSSpinLockLock(&mutex)

    if let ws = writerQueue.dequeue()
    { // data is already available
      OSSpinLockUnlock(&mutex)

      let context = UnsafePointer<T>(dispatch_get_context(ws))
      if context == UnsafePointer.null()
      { // not a normal code path.
        dispatch_semaphore_signal(nil)
        return nil
      }

      let element = context.memory
      dispatch_set_context(ws, nil)
      dispatch_semaphore_signal(ws)
      return element
    }

    if closed
    {
      OSSpinLockUnlock(&mutex)
      return nil
    }

    // wait for data from a writer
    let threadLock = SemaphorePool.dequeue()
    readerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&mutex)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = UnsafeMutablePointer<T>(dispatch_get_context(threadLock))
    if context == UnsafeMutablePointer.null()
    { // thread was awoken by a close(), not a writer
      SemaphorePool.enqueue(threadLock)
      return nil
    }

    let element = context.move()
    context.dealloc(1)
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)
    return element
  }
}
