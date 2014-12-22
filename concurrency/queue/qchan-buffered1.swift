//
//  qchan-buffered1.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a 1-element buffer.
*/

final class QBuffered1Chan<T>: Chan<T>
{
  private var e = UnsafeMutablePointer<T>.alloc(1)

  // housekeeping variables

  private let capacity = 1
  private var elements = 0

  private let readerQueue = ObjectQueue<dispatch_semaphore_t>()
  private let writerQueue = ObjectQueue<dispatch_semaphore_t>()

  private let mutex = dispatch_semaphore_create(1)!

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  deinit
  {
    if elements > 0
    {
      e.destroy()
    }
    e.dealloc(1)
  }

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return elements <= 0
  }

  final override var isFull: Bool
  {
    return elements >= capacity
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
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
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
    if self.closed { return false }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    while !self.closed &&  elements >= capacity
    {
      wait(mutex: mutex, queue: writerQueue)
    }

    if self.closed
    {
      dispatch_semaphore_signal(mutex)
      return false
    }

    e.initialize(newElement)
    elements += 1

    if readerQueue.count > 0
    {
      dispatch_semaphore_signal(readerQueue.dequeue()!)
    }

    if elements < capacity && writerQueue.count > 0
    {
      dispatch_semaphore_signal(writerQueue.dequeue()!)
    }

    dispatch_semaphore_signal(mutex)
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
    if self.closed && elements <= 0 { return nil }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    while !self.closed && elements <= 0
    {
      wait(mutex: mutex, queue: readerQueue)
    }

    if self.closed && elements <= 0
    {
      dispatch_semaphore_signal(mutex)
      return nil
    }

    let element = e.move()
    elements -= 1

    if writerQueue.count > 0
    {
      dispatch_semaphore_signal(writerQueue.dequeue()!)
    }

    if elements > 0 && readerQueue.count > 0
    {
      dispatch_semaphore_signal(readerQueue.dequeue()!)
    }

    dispatch_semaphore_signal(mutex)

    return element
  }
}
