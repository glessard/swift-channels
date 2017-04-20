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

infix operator <-: AssignmentPrecedence

/**
  Channel send operator: send a new element to a channel

  If the channel is full, sending will block.
  If the channel has been closed, sending will fail silently.

  Using this operator is equivalent to `_ = Sender<T>.send(t: T)`

  - parameter s: a SenderType
  - parameter element: the new element to be added to the underlying channel.
*/

public func <-<C: SenderType>(s: C, element: C.SentElement)
{
  s.send(element)
}


/**
  Channel receive operator, global definition
*/

prefix operator <-

/**
  Channel receive operator: receive the oldest element from a channel.

  If the channel is empty, receiving will block.
  If the channel is empty and closed, receiving will return nil.

  This is the equivalent of `Receiver<T>.receive()`

  - parameter r: a `ReceiverType`

  - returns: the oldest element from the underlying channel
*/

public prefix func <-<C: ReceiverType>(r: C) -> C.ReceivedElement?
{
  return r.receive()
}
