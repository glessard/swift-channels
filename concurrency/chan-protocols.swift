//
//  chan-protocols.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  The interface required for the receiving end of a channel.
*/

public protocol ReceivingChannel: class, BasicChannel, GeneratorType, SequenceType
{
  typealias ReceivedElement

  /**
    Report whether the channel is empty (and therefore isn't ready to be received from)
  */

  var isEmpty: Bool { get }

  /**
    Receive the oldest element from the channel.
    The channel will no longer hold a copy of (or reference to) the item.
    Used internally by the <- receive operator.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  func receive() -> ReceivedElement?

  /**
    Return the next element from the channel.
    This should be an alias for ReceivingChannel.receive() and will fulfill the GeneratorType protocol.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  func next() -> ReceivedElement?

  /**
    Return self as a GeneratorType.
    This fulfills the SequenceType protocol.

    :return: an implementor of GeneratorType to iterate along the channel's elements.
  */

  func generate() -> Self
}

/**
  The interface required for the sending end of a channel.
*/

public protocol SendingChannel: class, BasicChannel
{
  typealias SentElement

  /**
    Report whether the channel is full (and can't be sent to)
  */

  var isFull: Bool { get }

  /**
    Send a new element to the channel. The caller should probably not retain a
    reference to anything thus sent. Used internally by the <- send operator.

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be sent to the channel.
  */

  func send(newElement: SentElement)
}

/**
  Interface that any channel needs. Not useful by itself.
*/

public protocol BasicChannel: class
{
  /**
    Report whether the channel has been closed
  */

  var isClosed: Bool { get }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  func close()
}