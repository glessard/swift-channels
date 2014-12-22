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
  If the channel has been closed, sending will fail silently.

  The ideal situation when the channel has been closed
  would involve some error-handling, such as a panic() call.
  Unfortunately there is no such thing in Swift, so a silent failure it is.

  Using this operator is equivalent to '_ = Sender<T>.send(T)'

  The SenderType 'chan' is passed as inout because that's slightly faster.

  :param: chan
  :param: element the new element to be added to the channel.
*/

public func <-<C: SenderType>(inout chan: C, element: C.SentElement)
{
  chan.send(element)
}


/**
  Channel receive operator, global definition
*/

prefix operator <- {}

/**
  Channel receive operator: receive the oldest element from the channel.

  If the channel is empty, this call will block.
  If the channel is empty and closed, this will return nil.

  This is the equivalent of Receiver<T>.receive() -> T?
  
  The ReceiverType 'chan' is passed as inout because that's slightly faster.

  :param:  chan

  :return: the oldest element from the channel
*/

public prefix func <-<C: ReceiverType>(inout chan: C) -> C.ReceivedElement?
{
  return chan.receive()
}
