//
//  chan-gcd-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-30.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A one-element, buffered channel which will only ever transmit one message.
  The first successful write operation immediately closes the channel.
*/

final public class gcdSingletonChan<T>: gcdChan<T>
{
  private var element: T?

  // Housekeeping

  private var writerCount: Int64 = -1
  private var readerCount: Int64 = -1

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  public override init()
  {
    element = nil
    super.init()
  }

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

    if writer != 0
    { // if writer is not 0, this call is happening too late.
      return
    }

    element = newElement
    OSAtomicIncrement64Barrier(&elementsWritten)
    close()

    readers.resume()
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    let reader = OSAtomicIncrement64Barrier(&readerCount)

    while (elementsWritten < 0) && !self.closed
    {
      readers.mutex { // A suspended reader will block here
        if (self.elementsWritten < 0) && !self.closed
        {
          self.readers.suspend()
          return // to the top of the while loop and be suspended
        }
      }
    }

    let element: T? = {
      if reader == 0
      {
        if let e = self.element
        {
          OSAtomicIncrement64Barrier(&self.elementsRead)
          self.element = nil
          return e
        }
      }
      return nil
    }()

    return element
  }
}
