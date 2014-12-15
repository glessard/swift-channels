//
//  chan-buffered1.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

private let semaphorePool = ObjectQueue<dispatch_semaphore_t>()

private func poolEnqueue(s: dispatch_semaphore_t)
{
  semaphorePool.enqueue(s)
}

private func poolDequeue() -> dispatch_semaphore_t
{
  if let s = semaphorePool.dequeue()
  {
    return s
  }

  return dispatch_semaphore_create(0)!
}

/**
  A channel that uses a 1-element buffer.
*/

final class QBuffered1Chan<T>: Chan<T>
{
  private var element: T? = nil

  // housekeeping variables

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  private let readerQueue = ObjectQueue<dispatch_semaphore_t>()
  private let writerQueue = ObjectQueue<dispatch_semaphore_t>()

  private let semap = dispatch_semaphore_create(1)!

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return elementsWritten <= elementsRead
  }

  final override var isFull: Bool
  {
    return elementsWritten > elementsRead
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

    closed = true

    // Unblock the threads waiting on our conditions.
    if let s = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(s)
    }
    if let s = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(s)
    }
  }

  final func wait(#lock: dispatch_semaphore_t, queue: ObjectQueue<dispatch_semaphore_t>)
  {
    let threadLock = poolDequeue()
    queue.enqueue(threadLock)
    dispatch_semaphore_signal(lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
    poolEnqueue(threadLock)
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.closed { return }

    dispatch_semaphore_wait(semap, DISPATCH_TIME_FOREVER)
    while !self.closed && elementsWritten > elementsRead
    {
      wait(lock: semap, queue: writerQueue)
      dispatch_semaphore_wait(semap, DISPATCH_TIME_FOREVER)
    }

    if !self.closed
    {
      self.element = newElement
      elementsWritten += 1
    }

    if elementsWritten <= elementsRead || self.closed
    {
      if let s = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(s)
      }
    }
    dispatch_semaphore_signal(semap)

    if readerQueue.count > 0
    {
      if let s = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(s)
      }
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
    dispatch_semaphore_wait(semap, DISPATCH_TIME_FOREVER)
    while !self.closed && elementsWritten <= elementsRead
    {
      wait(lock: semap, queue: readerQueue)
      dispatch_semaphore_wait(semap, DISPATCH_TIME_FOREVER)
    }

    if self.closed && (elementsWritten == elementsRead)
    {
      self.element = nil
    }

    let oldElement = self.element
    elementsRead += 1

    // Whether to set self.element to nil is an interesting question.
    // If T is a reference type (or otherwise contains a reference), then
    // nulling is desirable to in order to avoid unnecessarily extending the
    // lifetime of the referred-to element.
    // In the case of a potentially long-lived buffered channel, there is a
    // potential for contention at this point. This implementation is
    // choosing to take the risk of extending the life of its messages.
    // Also, setting self.element to nil at this point would be slow. Somehow.

    if elementsWritten > elementsRead || self.closed
    {
      if readerQueue.count > 0
      {
        if let s = readerQueue.dequeue()
        {
          dispatch_semaphore_signal(s)
        }
      }
    }
    dispatch_semaphore_signal(semap)

    if writerQueue.count > 0
    {
      if let s = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(s)
      }
    }

    return oldElement
  }
}
