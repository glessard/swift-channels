//
//  chan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A one-element channel which will only ever transmit one message:
  the first successful write operation closes the channel.
*/

final public class SingletonChan<T>: Chan<T>
{
  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    let channel = SingletonChan()
    return (Sender.Wrap(channel), Receiver.Wrap(channel))
  }

  public class func Make(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make()
  }

  private var element: T? = nil

  // housekeeping variables

  private var writerCount: Int64 = 0
  private var readerCount: Int64 = 0

  private var barrier = dispatch_semaphore_create(0)!

  private var closed = false

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return element == nil
  }

  final override var isFull: Bool
  {
    return element != nil
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

  override func put(newElement: T)
  {
    let writer = OSAtomicIncrement64Barrier(&writerCount)

    if writer > 1
    { // if this is not the first writer, the call is happening too late.
      return
    }

    element = newElement
    close() // also increments the 'barrier' semaphore
  }

  /**
    Return the element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the element transmitted through the channel.
  */

  override func get() -> T?
  {
    if !closed
    {
      dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER)
    }

    let reader = OSAtomicIncrement64Barrier(&readerCount)

    if reader == 1
    {
      if let e = element
      {
        element = nil
        dispatch_semaphore_signal(barrier)
        return e
      }
    }

    // if this is not the first reader, too late.
    dispatch_semaphore_signal(barrier)
    return nil
  }
}
