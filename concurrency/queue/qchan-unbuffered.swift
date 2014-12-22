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

  private let mutex = dispatch_semaphore_create(1)!

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

  final override func close()
  {
    if closed { return }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
    closed = true

    // Unblock the threads waiting on our conditions.
    while readerQueue.count > 0
    {
      dispatch_semaphore_signal(readerQueue.dequeue()!)
    }
    while writerQueue.count > 0
    {
      dispatch_semaphore_signal(writerQueue.dequeue()!)
    }
    dispatch_semaphore_signal(mutex)
  }

  /**
    Stop the thread on a new semaphore obtained from the SemaphorePool

    The new semaphore is enqueued to readerQueue or writerQueue, and
    will be used as a signal to resume the thread at a later time.

    :param: mutex a semaphore that is currently held by the calling thread.
    :param: queue the queue to which the signal should be appended
  */

  final func wait(#mutex: dispatch_semaphore_t, queue: ObjectQueue<dispatch_semaphore_t>)
  {
    let threadLock = SemaphorePool.dequeue()
    queue.enqueue(threadLock)
    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
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

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    let pointer = UnsafeMutablePointer<T>.alloc(1)
    pointer.initialize(newElement)

    if readerQueue.count > 0
    { // there is already an interested reader
      let rs = readerQueue.dequeue()!
      dispatch_semaphore_signal(mutex)
      dispatch_set_context(rs, pointer)
      dispatch_semaphore_signal(rs)
      return true
    }

    // enqueue a new semaphore along with our data
    let threadLock = SemaphorePool.dequeue()
    dispatch_set_context(threadLock, pointer)
    writerQueue.enqueue(threadLock)
    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken by a reader (or the channel was closed)
    let context = dispatch_get_context(threadLock)
    if context == pointer
    { // thread was awoken by close(), not a reader
      pointer.destroy()
      pointer.dealloc(1)
      dispatch_set_context(threadLock, nil)
      SemaphorePool.enqueue(threadLock)
      return false
    }

    assert(context == UnsafeMutablePointer.null(), "Memory leak at \(__FILE__), \(__LINE__)")

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

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    if writerQueue.count > 0
    { // data is already available
      let ws = writerQueue.dequeue()!
      dispatch_semaphore_signal(mutex)

      var element: T? = nil
      let context = UnsafeMutablePointer<T>(dispatch_get_context(ws))
      if context != UnsafeMutablePointer.null()
      {
        element = context.move()
        context.dealloc(1)
        dispatch_set_context(ws, nil)
      }
      dispatch_semaphore_signal(ws)
      return element
    }

    // wait for data from a writer
    let threadLock = SemaphorePool.dequeue()
    readerQueue.enqueue(threadLock)
    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken by a writer (or the channel was closed)
    var element: T? = nil
    let context = UnsafeMutablePointer<T>(dispatch_get_context(threadLock))
    if context != UnsafeMutablePointer.null()
    { // thread was awoken by a writer, not close()
      element = context.move()
      context.dealloc(1)
      dispatch_set_context(threadLock, nil)
    }
    SemaphorePool.enqueue(threadLock)
    return element
  }
}
