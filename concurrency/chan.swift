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

public class Chan<T>: ChannelType, SelectableChannelType
{
  /**
    Initialize a Chan<T>. Explicitly internal, not public.
  */

  init() {}

  // MARK: ChannelType interface

  /**
    Determine whether the channel is empty (and can't be received from)

    If only one thread can receive from the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be received from in more than one thread,
    as the empty state could go from false to true at any moment.
  */

  public var isEmpty: Bool { return true }

  /**
    Determine whether the channel is full (and can't be written to)

    If only one thread can send to the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be sent to by more than one thread,
    as the full state could go from false to true at any moment.
  */

  public var isFull: Bool { return false }

  /**
    Determine whether the channel has been closed
  */

  public var isClosed: Bool { return true }

  /**
    Close the channel
  
    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  public func close() { }

  /**
    Put a new element in the channel
  
    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken (apart from returning false).

    - parameter element: the new element to be added to the channel.
    - returns: whether or not the operation was successful.
  */

  public func put(newElement: T) -> Bool
  {
    return false
  }

  /**
    Take the oldest element from the channel.

    If the channel is empty and closed, this will return nil.
    If the channel is empty (but not closed), this call will block.

    - returns: the oldest element from the channel.
  */

  public func get() -> T?
  {
    return nil
  }

  // MARK: SelectableChannelType interface

  func selectGet(select: ChannelSemaphore, selection: Selection)
  {
    if select.setState(.Invalidated)
    {
      select.signal()
    }
  }

  func extract(selection: Selection) -> T?
  {
    return nil
  }

  func selectPut(select: ChannelSemaphore, selection: Selection)
  {
    if select.setState(.Invalidated)
    {
      select.signal()
    }
  }

  func insert(selection: Selection, newElement: T) -> Bool
  {
    return false
  }

  // MARK: Chan Factory Functions

  /**
    Factory function to obtain a new `Chan<T>` of the desired channel capacity.
    If capacity is 0, then an unbuffered channel will be created.

    - parameter capacity: the buffer capacity of the channel.
    - returns: a newly-created, empty `Chan<T>`
  */

  public static func Make(capacity: Int) -> Chan<T>
  {
    switch capacity < 1
    {
    case true:
      return QUnbufferedChan<T>()

    default:
      return SBufferedChan<T>(capacity)
    }
  }

  /**
    Factory function to obtain a new, unbuffered `Chan<T>` object (channel capacity = 0).

    - returns: a newly-created, empty `Chan<T>`
  */

  public static func Make() -> Chan<T>
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new `Chan<T>` object, using a type object to determine the type.

    - parameter type: a type object to determine the channel's element type. The object is discarded.
    - parameter capacity: the buffer capacity of the channel. Default is 0, meaning an unbuffered channel.

    - returns: a newly-created, empty `Chan<T>`
  */

  public static func Make(_: T.Type, _ capacity: Int = 0) -> Chan<T>
  {
    return Make(capacity)
  }

  /**
    Factory function to obtain a new single-message `Chan<T>` object. The returned channel will
    transmit at most one message during its lifetime, and will become closed in the process.
    
    - returns: a new single-message `Chan<T>`
  */

  public static func MakeSingleton() -> Chan<T>
  {
    return SingletonChan()
  }
}
