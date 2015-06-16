//
//  chan-sender.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Sender<T> is the sending endpoint for a Channel, Chan<T>.
*/

public struct Sender<T>: SenderType
{
  private let wrapped: Chan<T>

  public init(_ c: Chan<T>)
  {
    wrapped = c
  }

  init()
  {
    wrapped = Chan()
  }

  // MARK: SenderType implementation

  public var isClosed: Bool { return wrapped.isClosed }
  public func close()  { wrapped.close() }

  public func send(newElement: T) -> Bool { return wrapped.put(newElement) }
}

/**
  Channel send operator: send a new element to the channel

  If the channel is full, this call will block.
  If the channel has been closed, sending will fail silently.

  The ideal situation when the channel has been closed
  would involve some error-handling, such as a panic() call.
  Unfortunately there is no such thing in Swift, so a silent failure it is.

  Using this operator is equivalent to '_ = Sender<T>.send(T)'

  - parameter s: a Sender<T>
  - parameter element: the new T to be added to the channel.
*/

public func <-<T>(s: Sender<T>, element: T)
{
  s.wrapped.put(element)
}

// MARK: Sender factory functions

extension Sender
{
  /**
    Return a new Sender<T> to act as the sending endpoint for a Chan<T>.

    - parameter c: A Chan<T> object
    - returns:  A Sender<T> object that will send elements to the Chan<T>
  */

  public static func Wrap(c: Chan<T>) -> Sender<T>
  {
    return Sender(c)
  }

  /**
    Return a new Sender<T> to act as the sending enpoint for a ChannelType

    - parameter c: An object that implements ChannelType
    - returns:  A Sender<T> object that will send elements to c
  */

  static func Wrap<C: ChannelType where C.Element == T>(c: C) -> Sender<T>
  {
    if let chan = c as? Chan<T>
    {
      return Sender(chan)
    }

    return Sender(ChannelTypeAsChan(c))
  }

  /**
    Return a new Sender<T> to stand in for SenderType c.

    If c is a Sender, c will be returned directly.
    If c is any other kind of SenderType, it will be wrapped in a type-hidden way.

    - parameter c: A SenderType implementor to be wrapped by a Sender object.
    - returns:  A Sender object that will pass along the elements to c.
  */

  public static func Wrap<C: SenderType where C.SentElement == T>(c: C) -> Sender<T>
  {
    if let s = c as? Sender<T>
    {
      return s
    }

    return Sender(SenderTypeAsChan(c))
  }
}

/**
  ChannelTypeAsChan<T,C> disguises any ChannelType as a Chan<T>, for use by Sender<T>
*/

private class ChannelTypeAsChan<T, C: ChannelType where C.Element == T>: Chan<T>
{
  private var wrapped: C

  init(_ c: C)
  {
    wrapped = c
  }

  override var isClosed: Bool { return wrapped.isClosed }
  override func close()  { wrapped.close() }

  override func put(newElement: T) -> Bool { return wrapped.put(newElement) }
}

/**
  SenderTypeAsChan<T,C> disguises any SenderType as a Chan<T>, for use by Sender<T>
*/

private class SenderTypeAsChan<T, C: SenderType where C.SentElement == T>: Chan<T>
{
  private var wrapped: C

  init(_ sender: C)
  {
    wrapped = sender
  }

  override var isClosed: Bool { return wrapped.isClosed }
  override func close()  { wrapped.close() }

  override func put(newElement: T) -> Bool { return wrapped.send(newElement) }
}
