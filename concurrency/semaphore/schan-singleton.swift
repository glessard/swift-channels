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

  private var element: T? = nil

  private var writerCount: Int32 = 0
  private var readerCount: Int32 = 0

  private var barrier = dispatch_group_create()!

  private var closedState: Int32 = 0

  // MARK: Initialization

  override init()
  {
    dispatch_group_enter(barrier)
  }

  convenience init(_ element: T)
  {
    self.init()
    self.element = element
    close()
  }

  // MARK: Property accessors

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
      dispatch_group_leave(barrier)
    }
  }

  /**
    Append an element to the channel

    This method will not block because only one send operation
    can occur in the lifetime of a SingletonChan.

    The first successful send will close the channel; further
    send operations will have no effect.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if writerCount == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &writerCount)
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

  override func get() -> T?
  {
    if closedState == 0
    {
      dispatch_group_wait(barrier, DISPATCH_TIME_FOREVER)
    }

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

  override func selectPutNow(selection: Selection) -> Selection?
  {
    return writerCount == 0 ? selection : nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    return put(newElement)
  }

  override func selectPut(semaphore: SemaphoreChan, selection: Selection)
  {
    // If we get here, it would be as a result of an inconceivable set of circumstances.
    if let s = semaphore.get()
    {
      if self.writerCount == 0
      {
        s.setStatus(.Select(selection))
      }
      s.signal()
    }
  }

  override func selectGetNow(selection: Selection) -> Selection?
  {
    return readerCount == 0 ? selection : nil
  }

  override func extract(selection: Selection) -> T?
  {
    if readerCount == 0 && writerCount == 1 && OSAtomicCompareAndSwap32Barrier(0, 1, &readerCount)
    { // Only one thread can get here.
      if let e = element
      {
        element = nil
        return e
      }
    }
    return nil
  }

  override func selectGet(semaphore: SemaphoreChan, selection: Selection)
  {
    if self.closedState != 0
    {
      if let s = semaphore.get()
      {
        if self.readerCount == 0
        {
          s.setStatus(.Select(selection))
        }
        s.signal()
      }
      return
    }

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      if self.closedState == 0
      {
        dispatch_group_wait(self.barrier, DISPATCH_TIME_FOREVER)
      }

      if let s = semaphore.get()
      {
        if self.readerCount == 0
        {
          s.setStatus(.Select(selection))
        }
        s.signal()
      }
    }
  }
}
