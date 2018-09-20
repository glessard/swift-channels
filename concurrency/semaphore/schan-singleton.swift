//
//  chan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A one-element buffered channel which will only ever transmit one message:
  the first successful write operation closes the channel.

  The set of transmitted messages is (at most) a singleton set;
  not to be confused with the Singleton (anti?)pattern.
*/

final class SingletonChan<T>: Chan<T>
{
  // MARK: Private instance variables

  fileprivate var element: T? = nil

  fileprivate var writerCount: Int32 = 0
  fileprivate var readerCount: Int32 = 0

  fileprivate var barrier = DispatchGroup()

  fileprivate var closedState: Int32 = 0

  // MARK: Initialization

  override init()
  {
    barrier.enter()
  }

  convenience init(_ element: T)
  {
    self.init()
    self.put(element)
    self.close()
  }

  // MARK: Property accessors

  final override var isEmpty: Bool { return element == nil }

  final override var isFull: Bool { return element != nil }

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closedState > 0 }

  // MARK: ChannelType implementation

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  override func close()
  {
    if closedState == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &closedState)
    { // Only one thread can get here
      barrier.leave()
    }
  }

  /**
    Append an element to the channel

    This method will not block because only one send operation
    can occur in the lifetime of a SingletonChan.

    The first successful send will close the channel; further
    send operations will have no effect.

    - parameter element: the new element to be added to the channel.
  */

  @discardableResult
  override func put(_ newElement: T) -> Bool
  {
    if writerCount == 0 && closedState == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &writerCount)
    { // Only one thread can get here
      element = newElement
      self.close() // also increments the 'barrier' semaphore
      return true
    }

    // not the first writer, too late.
    return false
  }

  /**
    Return the element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    - returns: the element transmitted through the channel.
  */

  override func get() -> T?
  {
    if closedState == 0 && writerCount == 0
    {
      _ = barrier.wait(timeout: DispatchTime.distantFuture)
    }

    return getElement()
  }

  fileprivate func getElement() -> T?
  {
    assert(writerCount != 0 || closedState != 0, #function)
    if readerCount == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &readerCount)
    { // Only one thread can get here.
      if let e = element
      {
        element = nil
        return e
      }
    }
    return nil
  }

  // MARK: SelectableChannelType methods

  override func insert(_ selection: Selection, newElement: T) -> Bool
  {
    return self.put(newElement)
  }

  override func selectPut(_ select: ChannelSemaphore, selection: Selection)
  {
    if closedState == 0 && writerCount == 0 && select.setState(.select)
    {
      select.selection = selection
      select.signal()
    }
  }

  override func extract(_ selection: Selection) -> T?
  {
    return getElement()
  }

  override func selectGet(_ select: ChannelSemaphore, selection: Selection)
  {
    if closedState != 0 && select.setState(.select)
    {
      select.selection = selection
      select.signal()
      return
    }

    barrier.notify(queue: DispatchQueue.global(qos: DispatchQoS.current.qosClass)) {
      if select.setState(.select)
      {
        select.selection = selection
        select.signal()
      }
    }
  }
}
