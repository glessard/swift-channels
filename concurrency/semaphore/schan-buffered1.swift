//
//  chan-buffered1.swift
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

final class SBuffered1Chan<T>: Chan<T>
{
  private var e = UnsafeMutablePointer<T>.alloc(1)

  // housekeeping variables

  private let capacity = 1
  private var elements = 0

  private let filled = dispatch_semaphore_create(0)!
  private let empty =  dispatch_semaphore_create(1)!

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

  override func close()
  {
    if closed { return }

    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)
    closed = true
    dispatch_semaphore_signal(mutex)

    dispatch_semaphore_signal(filled)
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
      e.initialize(newElement)
      elements += 1
    }

    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_signal(filled)
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

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)
    dispatch_semaphore_wait(mutex, DISPATCH_TIME_FOREVER)

    if closed && elements <= 0
    {
      dispatch_semaphore_signal(filled)
      dispatch_semaphore_signal(mutex)
      return nil
    }

    let element = e.move()
    elements -= 1

    // When T is a reference type (or otherwise contains a reference),
    // nulling is desirable.
    // But somehow setting an optional class member to nil is slow, so we won't do it.

    dispatch_semaphore_signal(mutex)
    dispatch_semaphore_signal(empty)

    return element
  }
}
