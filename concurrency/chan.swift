//
//  chan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  A channel allows concurrently executing tasks to communicate by sending and
  receiving data of a specific type.

  The factory class function Make(capacity: Int) returns a Chan instance that is buffered
  (if capacity > 0), or unbuffered (if capacity is 0). The no-parameter version
  of the factory function returns an unbuffered channel.
*/

class Chan<T>: ChannelType
{
  // Computed properties

  /**
    Determine whether the channel is empty (and therefore can't be received from)
  */

  var isEmpty: Bool { return true }

  /**
    Determine whether the channel is full (and can't be written to)
  */

  var isFull: Bool { return true }

  /**
    Determine whether the channel has been closed
  */

  var isClosed: Bool { return true }

  /**
    Close the channel
  
    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  func close() { }

  /**
    Put a new element in the channel
  
    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  func put(newElement: T)
  {
    _ = newElement
  }

  /**
    Take the oldest element from the channel.

    If the channel is empty and closed, this will return nil.
    If the channel is empty (but not closed), this call will block.

    :return: the oldest element from the channel.
  */

  func get() -> T?
  {
    return nil
  }
}
