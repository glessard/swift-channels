//
//  chan-receiver.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Receiver<T> is a receiving endpoint for a `ChannelType`.
*/

public final class Receiver<T>: ReceiverType
{
  private let wrapped: Chan<T>

  /**
    Initialize a new `Receiver<T>` to act as the receiving endpoint for a `Chan<T>`.

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

  // MARK: ReceiverType implementation

  public var isClosed: Bool { return wrapped.isClosed }
  public var isEmpty:  Bool { return wrapped.isEmpty }
  public func close()  { wrapped.close() }

  public func receive() -> T?
  {
    return wrapped.get()
  }
}

extension Receiver: Selectable
{
  // MARK: Selectable implementation
  
  public func selectNotify(select: ChannelSemaphore, selection: Selection)
  {
    wrapped.selectGet(select, selection: selection)
  }

  /**
    A `ReceiverType` is selectable as long as the channel still contains elements.
  
    - returns: `true` if the channel still contains elements.
  */

  public var selectable: Bool
  {
    return !(wrapped.isClosed && wrapped.isEmpty)
  }
}

extension Receiver: SelectableReceiverType
{
  // MARK: SelectableReceiverType implementation
  
  public func extract(selection: Selection) -> T?
  {
    precondition(selection.id === self, __FUNCTION__)
    return wrapped.extract(selection)
  }
}

/**
  Channel receive operator: receive the oldest element from the channel.

  If the channel is empty, this call will block.
  If the channel is empty and closed, this will return `nil`.

  This is the equivalent of `Receiver<T>.receive()`

  - parameter r: a `Receiver`

  - returns: the oldest element from the channel, or `nil`
*/

public prefix func <-<T>(r: Receiver<T>) -> T?
{
  return r.wrapped.get()
}

// MARK: Receiver factory functions

extension Receiver
{
  /**
    Return a new `Receiver<T>` to act as the receiving endpoint for a `Chan<T>`.

    - parameter c: A `Chan<T>` object
    - returns:  A `Receiver<T>` that will receive elements from `c`
  */

  public static func Wrap(c: Chan<T>) -> Receiver<T>
  {
    return Receiver(c)
  }

  /**
    Return a new `Receiver` to act as the receiving endpoint for a `ChannelType`.

    - parameter c: An object that implements `ChannelType`
    - returns:  A `Receiver` object that will receive elements from `c`
  */

  static func Wrap<C: ChannelType where C.Element == T>(c: C) -> Receiver<T>
  {
    if let chan = c as? Chan<T>
    {
      return Receiver(chan)
    }

    return Receiver(ChannelTypeAsChan(c))
  }

  /**
    Return a new `Receiver` to stand in for another `ReceiverType`.

    If `r` is a `Receiver`, it will be returned directly.
    If `r` is any other kind of `ReceiverType`, it will be wrapped in a new `Receiver`.

    - parameter r: An object that implements `ReceiverType`.
    - returns:  A `Receiver` object that will pass along the elements from `r`.
  */

  public static func Wrap<R: ReceiverType where R.ReceivedElement == T>(r: R) -> Receiver<T>
  {
    if let r = r as? Receiver<T>
    {
      return r
    }

    return Receiver(ReceiverTypeAsChan(r))
  }
}

/**
  ChannelTypeAsChan<T,C> disguises any ChannelType as a Chan<T>,
  for use by Receiver<T>
*/

private class ChannelTypeAsChan<T, C: ChannelType where C.Element == T>: Chan<T>
{
  private var wrapped: C

  init(_ c: C)
  {
    wrapped = c
  }

  override var isClosed: Bool { return wrapped.isClosed }
  override var isEmpty:  Bool { return wrapped.isEmpty }
  override func close()  { wrapped.close() }

  override func get() -> T? { return wrapped.get() }
}

/**
  ReceiverTypeAsChan<T,C> disguises any ReceiverType as a Chan<T>,
  for use by Receiver<T>
*/

private class ReceiverTypeAsChan<T, C: ReceiverType where C.ReceivedElement == T>: Chan<T>
{
  private var wrapped: C

  init(_ receiver: C)
  {
    wrapped = receiver
  }

  override var isClosed: Bool { return wrapped.isClosed }
  override var isEmpty:  Bool { return wrapped.isEmpty }
  override func close()  { wrapped.close() }

  override func get() -> T? { return wrapped.receive() }
}
