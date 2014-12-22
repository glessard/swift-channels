//
//  qchan-bufferedN.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a queue to store its elements.
*/

final class QBufferedNChan<T>: Chan<T>
{
  private var buffer: UnsafeMutablePointer<T>

  // housekeeping variables

  private let capacity: Int
  private let mask: Int

  private var head = 0
  private var tail = 0

  private var headptr: UnsafeMutablePointer<T>
  private var tailptr: UnsafeMutablePointer<T>

  private let readerQueue = ObjectQueue<dispatch_semaphore_t>()
  private let writerQueue = ObjectQueue<dispatch_semaphore_t>()

  private let mutex = dispatch_semaphore_create(1)!

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
    headptr = buffer
    tailptr = buffer

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
      if (i&mask == 0) { headptr = buffer }
      headptr.destroy()
      headptr = headptr.successor()
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

    while !self.closed && head+capacity <= tail
    {
      wait(mutex: mutex, queue: writerQueue)
    }

    if self.closed
    {
      dispatch_semaphore_signal(mutex)
      return false
    }

    tailptr.initialize(newElement)
    tailptr = tailptr.successor()
    tail += 1
    if (tail&mask == 0) { tailptr = buffer }

    if readerQueue.count > 0
    {
      dispatch_semaphore_signal(readerQueue.dequeue()!)
    }

    if head+capacity < tail && writerQueue.count > 0
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
    if self.closed && head >= tail { return nil }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    while !self.closed && head >= tail
    {
      wait(mutex: mutex, queue: readerQueue)
    }

    if self.closed && head >= tail
    {
      dispatch_semaphore_signal(mutex)
      return nil
    }

    let element = headptr.move()
    headptr = headptr.successor()
    head += 1
    if (head&mask == 0) { headptr = buffer }

    if writerQueue.count > 0
    {
      dispatch_semaphore_signal(writerQueue.dequeue()!)
    }

    if head < tail && readerQueue.count > 0
    {
      dispatch_semaphore_signal(readerQueue.dequeue()!)
    }

    dispatch_semaphore_signal(mutex)

    return element
  }
}
