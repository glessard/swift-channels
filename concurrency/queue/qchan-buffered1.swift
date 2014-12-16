//
//  chan-buffered1.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

private struct SemaphorePool
{
  static let poolq = ObjectQueue<dispatch_semaphore_t>()

  static func enqueue(s: dispatch_semaphore_t)
  {
    poolq.enqueue(s)
  }

  static func dequeue() -> dispatch_semaphore_t
  {
    if let s = poolq.dequeue()
    {
      return s
    }

    return dispatch_semaphore_create(0)!
  }
}

/**
  A channel that uses a 1-element buffer.
*/

final class QBuffered1Chan<T>: Chan<T>
{
  private var element: T? = nil

  // housekeeping variables

  private let capacity: Int32 = 1
  private var elements: Int32 = 0

  private let readerQueue = ObjectQueue<dispatch_semaphore_t>()
  private let writerQueue = ObjectQueue<dispatch_semaphore_t>()

  private let mutex = dispatch_semaphore_create(1)!

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

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
    while let rs = readerQueue.dequeue()
    {
      dispatch_semaphore_signal(rs)
    }
    while let ws = writerQueue.dequeue()
    {
      dispatch_semaphore_signal(ws)
    }
    dispatch_semaphore_signal(mutex)
  }

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

  override func put(newElement: T)
  {
    if self.closed { return }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    while !self.closed &&  elements >= capacity
    {
      wait(mutex: mutex, queue: writerQueue)
      dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
    }

    if self.closed
    {
      dispatch_semaphore_signal(mutex)
      return
    }

    element = newElement
    elements += 1

    if readerQueue.count > 0
    {
      if let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
    }

    if elements < capacity && writerQueue.count > 0
    {
      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
    }

    dispatch_semaphore_signal(mutex)
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
      dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
    }

    if self.closed && elements <= 0
    {
      dispatch_semaphore_signal(mutex)
      return nil
    }

    let oldElement = element
//    element = nil
    elements -= 1

    // Whether to set self.element to nil is an interesting question.
    // When T is a reference type (or otherwise contains a reference),
    // nulling is desirable.
    // But somehow setting an optional class member to nil is slow, so we won't do it.

    if writerQueue.count > 0
    {
      if let ws = writerQueue.dequeue()
      {
        dispatch_semaphore_signal(ws)
      }
    }

    if elements > 0 && readerQueue.count > 0
    {
      if let rs = readerQueue.dequeue()
      {
        dispatch_semaphore_signal(rs)
      }
    }

    dispatch_semaphore_signal(mutex)

    return oldElement
  }
}
