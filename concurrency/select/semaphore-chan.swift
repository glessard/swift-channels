//
//  chan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A channel which holds one semaphore.
*/

final public class SemaphoreChan: ChannelType
{
  private let semaphore: dispatch_semaphore_t

  // housekeeping variables

  private var readerCount: Int32 = 0

  public init(_ newElement: dispatch_semaphore_t)
  {
    semaphore = newElement
  }

  // Computed property accessors

  final public var isEmpty: Bool
  {
    return readerCount > 0
  }

  final public var isFull: Bool
  {
    return readerCount < 1
  }

  /**
    Determine whether the channel has been closed
  */

  final public var isClosed: Bool { return true }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  public func close()
  {
  }

  /**
    Fail to append an element to the channel

    This method will not block because only one send operation
    can occur in the lifetime of this channel, and it has already happened on init.

    :param: element the new element to be added to the channel.
    :return: false
  */

  public func put(newElement: dispatch_semaphore_t) -> Bool
  {
    return false
  }

  /**
    Return the element from the channel.

    If this is the first time called, the semaphore will be returned.
    Otherwise, this will return nil.

    :return: the element transmitted through the channel, or nil
  */

  public func get() -> dispatch_semaphore_t?
  {
    if readerCount < 1
    {
      let reader = OSAtomicIncrement32Barrier(&readerCount)
      if reader == 1
      {
        return semaphore
      }
    }
    // if this is not the first reader, too late.
    return nil
  }
}
