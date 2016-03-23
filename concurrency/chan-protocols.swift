//
//  chan-protocols.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  The interface required for the receiving end of a channel.

  `ReceiverType` includes default implementations for `SequenceType` and `GeneratorType`.
  Note that iterating over a `ReceiverType` uses the `ReceiverType.receive()` method, which is a destructive operation.
*/

// MARK: ReceiverType

public protocol ReceiverType: BasicChannelType, GeneratorType, SequenceType
{
  associatedtype ReceivedElement

  /**
    Report whether the channel is empty (and therefore isn't ready to be received from)
  
    If only one thread can receive from the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be received from in more than one thread,
    as the empty state could go from false to true at any moment.
  */

  var isEmpty: Bool { get }

  /**
    Receive the oldest element from the channel.
    Used internally by the `<-` receive operator.

    If the underlying channel is open and empty, this call will block.
    If the underlying channel is closed and empty, this will return `nil`.
    If the underlying channel is not empty, this call will return a `ReceivedElement` item.

    - Note:    The channel will no longer hold a copy of (or reference to) the item.

    - Returns: the oldest element from the channel, or `nil` if the channel is closed and empty.
  */

  func receive() -> ReceivedElement?
}

// MARK: GeneratorType and SequenceType default implementations

public extension ReceiverType
{
  /**
    Return the next element from the channel.
    This is an alias for `ReceiverType.receive()` and will fulfill the `GeneratorType` protocol.

    If the underlying channel is open and empty, this call will block.
    If the underlying channel is closed and empty, this will return `nil`.
    If the underlying channel is not empty, this call will return a `ReceivedElement` item.

    - Note:    The channel will no longer hold a copy of (or reference to) the item.

    - Returns: the oldest element from the channel, or `nil` if the channel is closed and empty.
  */

  public func next() -> ReceivedElement?
  {
    return receive()
  }
}

/**
  The interface required for the sending end of a channel.
*/

// MARK: SenderType

public protocol SenderType: BasicChannelType
{
  associatedtype SentElement

  /**
    Report whether the channel is full (and can't be sent to)

    If only one thread can send to the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be sent to by more than one thread,
    as the full state could go from false to true at any moment.
  */

  var isFull: Bool { get }

  /**
    Send a new element to the channel. The caller should probably not retain a
    reference to anything thus sent. Used internally by the `<-` send operator.

    If the channel is full, this method will block.
    If the operation succeeds, this method will return `true`
    If the channel is closed, this method will return `false`.

    - parameter element: the new element to be sent to the channel.
    - returns: whether newElement was succesfully sent to the channel.
  */

  func send(newElement: SentElement) -> Bool
}

/**
  Interface that any channel needs. Not useful by itself.
*/

// MARK: BasicChannelType

public protocol BasicChannelType
{
  /**
    Report whether the channel has been closed
  
    - Returns: whether the channel has been closed
  */

  var isClosed: Bool { get }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    - Note: It could be considered an error to close a channel that has already been closed.
            The current behaviour is to do nothing.
  */

  mutating func close()
}

/**
  `ChannelType` is the connection between a `SenderType` and  `ReceiverType`.
*/

// MARK: ChannelType

protocol ChannelType: class, BasicChannelType
{
  associatedtype Element

  /**
    Determine whether the channel is empty (and can't be received from at the moment)
  
    If only one thread can receive from the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be received from in more than one thread,
    as the empty state could go from false to true at any moment.

  - Returns: `true` if the channel is empty.
  */

  var isEmpty: Bool { get }

  /**
    Determine whether the channel is full (and can't be written to at the moment)

    If only one thread can send to the channel, this can be useful to avoid a blocking call.
    That usage is not reliable if the channel can be sent to by more than one thread,
    as the full state could go from false to true at any moment.

    - Returns: `true` if the channel is full.
  */

  var isFull: Bool { get }

  /**
    Put a new element in the channel

    If the channel is full, this method will block.
    If the operation succeeds, this method will return `true`
    If the channel is closed, this method will return `false`.

    - parameter element: the new element to be added to the channel.
    - returns: whether newElement was succesfully inserted in the channel
  */

  func put(newElement: Element) -> Bool

  /**
    Obtain the oldest element from the channel.

    If the channel is open and empty, this call will block.
    If the channel is closed and empty, this will return `nil`.
    If the underlying channel is not empty, this call will return a `Element` item.

    - Note:    The channel will no longer hold a copy of (or reference to) the item.

    - returns: the oldest element from the channel, or `nil`
  */

  func get() -> Element?
}
