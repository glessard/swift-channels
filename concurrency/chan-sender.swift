//
//  chan-sender.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Sender<T> is a sending endpoint for a `ChannelType`
*/

public final class Sender<T>: SenderType
{
  private let wrapped: Chan<T>

  /**
    Initialize new `Sender<T>` to act as the sending endpoint for a `Chan<T>`.

    - parameter c: A `Chan<T>` object
  */

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
  public var isFull:   Bool { return wrapped.isFull }
  public func close()  { wrapped.close() }

  public func send(newElement: T) -> Bool { return wrapped.put(newElement) }
}

extension Sender: Selectable
{
  // MARK: Selectable implementation

  /**
    A `SenderType` is selectable as long as the channel is open.

    - returns: `true` if the channel is open.
  */

  public var selectable: Bool { return !wrapped.isClosed }

  public func selectNotify(select: ChannelSemaphore, selection: Selection)
  {
    wrapped.selectPut(select, selection: selection)
  }
}

extension Sender: SelectableSenderType
{
  // MARK: SelectableSenderType implementation

  public func insert(selection: Selection, newElement: T) -> Bool
  {
    precondition(selection.id === self, __FUNCTION__)
    return wrapped.insert(selection, newElement: newElement)
  }
}

/**
  Channel send operator: send a new element to the channel

  If the channel is full, this call will block.
  If the channel has been closed, sending will fail silently.

  Using this operator is equivalent to '_ = Sender<T>.send(t: T)'

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
    Return a new `Sender<T>` to act as the sending endpoint for a `Chan<T>` object.

    - parameter c: A `Chan<T>` object
    - returns:  A `Sender<T>` object that will send elements to `c`
  */

  public static func Wrap(c: Chan<T>) -> Sender<T>
  {
    return Sender(c)
  }

  /**
    Return a new `Sender` to act as the sending enpoint for a `ChannelType`

    - parameter c: An object that implements `ChannelType`
    - returns:  A `Sender` object that will send elements to `c`
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
    Return a new `Sender` to stand in for another `SenderType`.

    If `s` is a Sender, it will be returned directly.
    If `s` is any other kind of `SenderType`, it will be wrapped in a new `Sender`.

    - parameter `s`: An object that implements `SenderType`.
    - returns:  A Sender object that will pass along elements to `c`.
  */

  public static func Wrap<S: SenderType where S.SentElement == T>(s: S) -> Sender<T>
  {
    if let s = s as? Sender<T>
    {
      return s
    }

    return Sender(SenderTypeAsChan(s))
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
  override var isFull:   Bool { return wrapped.isFull }
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
  override var isFull:   Bool { return wrapped.isFull }
  override func close()  { wrapped.close() }

  override func put(newElement: T) -> Bool { return wrapped.send(newElement) }
}
