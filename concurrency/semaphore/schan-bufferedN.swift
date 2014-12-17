//
//  chan-bufferedN.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  This solution adapted from:
  Oracle Multithreaded Programming Guide, Chapter 4, section 5: "Semaphores"
  http://docs.oracle.com/cd/E19455-01/806-5257/6je9h032s/index.html
*/

final class SBufferedNChan<T>: Chan<T>
{
  private var q = AnythingQueue<T>()

  // housekeeping variables

  private let capacity: Int
  private var elements = 0

  private let avail: dispatch_semaphore_t
  private let empty: dispatch_semaphore_t

  private let mutex = dispatch_semaphore_create(1)!

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    avail = dispatch_semaphore_create(0)
    empty = dispatch_semaphore_create(capacity)

    super.init()
  }

  convenience override init()
  {
    self.init(1)
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

  override func close()
  {
    if closed { return }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
    closed = true
    dispatch_semaphore_signal(mutex)

    dispatch_semaphore_signal(avail)
    dispatch_semaphore_signal(empty)
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  final override func put(newElement: T)
  {
    if self.closed { return }

    dispatch_semaphore_wait(empty, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    if !closed
    {
      q.enqueue(newElement)
      elements += 1
    }

    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_signal(avail)
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  final override func get() -> T?
  {
    if self.closed && elements <= 0 { return nil }

    dispatch_semaphore_wait(avail, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    if closed && elements <= 0
    {
      dispatch_semaphore_signal(avail)
      dispatch_semaphore_signal(mutex)
      return nil
    }

    let oldElement = q.dequeue()
    elements -= 1

    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_signal(empty)

    return oldElement
  }
}
