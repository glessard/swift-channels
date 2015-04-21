//
//  semaphore-chan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-02-11.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A channel which holds one semaphore.
*/

final public class SemaphoreChan: ChannelType
{
  private let semaphore: ChannelSemaphore
  private var lock: Int32 = 0

  public init(_ newElement: ChannelSemaphore)
  {
    semaphore = newElement
  }

  // Computed property accessors

  final public var isEmpty: Bool  { return lock != 0 }
  final public var isFull: Bool   { return lock == 0 }

  final public var isClosed: Bool { return true }

  /**
    Close the channel

    The channel is created as closed, so this has no effect
  */

  public func close() {}

  /**
    Fail to append an element to the channel.
    This method will return false because the channel is already closed.

    :param: element the new element to be added to the channel.
    :return: false
  */

  public func put(newElement: ChannelSemaphore) -> Bool
  {
    return false
  }

  /**
    Return the element from the channel.

    If this is the first time called, the semaphore will be returned.
    Otherwise, this will return nil.

    :return: the element transmitted through the channel, or nil
  */

  public func get() -> ChannelSemaphore?
  {
    if lock == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &lock)
    {
      return semaphore
    }

    // if this is not the first reader, too late.
    return nil
  }
}
