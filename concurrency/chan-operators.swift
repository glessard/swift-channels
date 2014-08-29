//
//  chan-operators.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-18.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//


/**
  Channel send operator, global definition
  The precedence value chosen matches the assigment operators.
*/

infix operator <- { associativity left precedence 90}

/**
  Channel send operator: send a new element to the channel

  If the channel is full, this call will block.
  If the channel has been closed, an assertion may fail.

  This is the equivalent of Chan<T>.write(T)

  :param:  chan
  :param:  element the new element to be added to the channel.

  :return: the channel just written to, enabling multiple sends in one line.
*/

public func <-<C: WritableChannel>(chan: C, element: C.WrittenElement) -> C
{
  chan.write(element)
  return chan
}


/**
  Channel receive operator, global definition
*/

prefix operator <- {}

/**
  Channel receive operator: receive the oldest element from the channel.

  If the channel is empty, this call will block.
  If the channel is empty and closed, this will return nil.

  This is the equivalent of Chan<T>.read() -> T?

  :return: the oldest element from the channel
*/

public prefix func <-<C: ReadableChannel>(var chan: C) -> C.ReadElement?
{
  return chan.read()
}
