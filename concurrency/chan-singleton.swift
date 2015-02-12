//
//  chan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A one-element channel which will only ever transmit one message:
  the first successful write operation closes the channel.
*/

final public class SingletonChan<T>: Chan<T>
{
  override public class func Make() -> Chan<T>
  {
    return SingletonChan()
  }

  public class func Make(#typeOf: T) -> Chan<T>
  {
    return Make()
  }

  public class func Make(_: T.Type) -> Chan<T>
  {
    return Make()
  }

  private var element: T? = nil

  // housekeeping variables

  private var writerCount: Int32 = 0
  private var readerCount: Int32 = 0

  private var barrier = dispatch_semaphore_create(0)!

  private var closed = false

  public override init() { }

  // Computed property accessors

  final public override var isEmpty: Bool
  {
    return element == nil
  }

  final public override var isFull: Bool
  {
    return element != nil
  }

  /**
    Determine whether the channel has been closed
  */

  final public override var isClosed: Bool { return closed }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  public override func close()
  {
    if closed { return }

    closed = true

    dispatch_semaphore_signal(barrier)
  }

  /**
    Append an element to the channel

    This method will not block because only one send operation
    can occur in the lifetime of a SingletonChan.

    The first successful send will close the channel; further
    send operations will have no effect.

    :param: element the new element to be added to the channel.
  */

  public override func put(newElement: T) -> Bool
  {
    if OSAtomicCompareAndSwap32Barrier(0, 1, &writerCount)
    { // Only one thread can get here
      element = newElement
      close() // also increments the 'barrier' semaphore
      return true
    }

    // not the first writer, too late.
    return false
  }

  /**
    Return the element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the element transmitted through the channel.
  */

  public override func get() -> T?
  {
    if !closed
    {
      dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER)
      dispatch_semaphore_signal(barrier)
    }

    if OSAtomicCompareAndSwap32Barrier(0, 1, &readerCount)
    { // Only one thread can get here.
      if let e = element
      {
        element = nil
        return e
      }
    }

    return nil
  }
}
