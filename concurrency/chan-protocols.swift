//
//  chan-protocols.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  The interface required for the reading (receiving) end of a channel.
*/

public protocol ReadableChannel: class, BasicChannel, GeneratorType, SequenceType
{
  typealias ReadElement

  /**
    Report whether the channel is empty (and therefore can't be read from)
  */

  var isEmpty: Bool { get }

  /**
    Read the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  func read() -> ReadElement?

  /**
    Return the next element from the channel.
    This should be an alias for ReadableChannel.read() and will fulfill the GeneratorType protocol.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  func next() -> ReadElement?

  /**
    Return self as GeneratorType.
    This fulfills the SequenceType protocol.

    :return: an implementor of GeneratorType to iterate along the channel's elements.
  */

  func generate() -> Self
}

/**
  The interface required for the writing (sending) end of a channel.
*/

public protocol WritableChannel: class, BasicChannel
{
  typealias WrittenElement

  /**
    Report whether the channel is full (and can't be written to)
  */

  var isFull: Bool { get }

  /**
  Write a new element to the channel

  If the channel is full, this call will block.
  If the channel has been closed, no action will be taken.

  :param: element the new element to be added to the channel.
  */

   func write(newElement: WrittenElement)
}

/**
  The interface any channel needs.
  Not useful by itself.
*/

public protocol BasicChannel: class
{
  /**
    Report the channel capacity
  */

  var capacity: Int { get }

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