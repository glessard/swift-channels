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

  convenience init()
  {
    self.init(Chan())
  }

  /**
    Initialize a new `Sender` to act as the sending enpoint for a `ChannelType`

    - parameter c: An object that implements `ChannelType`
  */

  convenience init<C: SelectableChannelType where C.Element == T>(channelType c: C)
  {
    if let chan = c as? Chan<T>
    {
      self.init(chan)
    }
    else
    {
      self.init(ChannelTypeAsChan(c))
    }
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
    Return a new `Sender` to stand in for another `SenderType`.

    If `s` is a Sender, it will be returned directly.
    If `s` is any other kind of `SenderType`, it will be wrapped in a new `Sender`.

    - parameter `s`: An object that implements `SenderType`.
    - returns:  A Sender object that will pass along elements to `c`.
  */

  public static func Wrap<S: SelectableSenderType where S.SentElement == T>(s: S) -> Sender<T>
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

private class ChannelTypeAsChan<T, C: SelectableChannelType where C.Element == T>: Chan<T>
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

  override func selectPut(select: ChannelSemaphore, selection: Selection) { wrapped.selectPut(select, selection: selection) }
  override func insert(selection: Selection, newElement: T) -> Bool { return wrapped.insert(selection, newElement: newElement) }
}

/**
  SenderTypeAsChan<T,C> disguises any SenderType as a Chan<T>, for use by Sender<T>
*/

private class SenderTypeAsChan<T, S: SelectableSenderType where S.SentElement == T>: Chan<T>
{
  private var wrapped: S

  init(_ sender: S)
  {
    wrapped = sender
  }

  override var isClosed: Bool { return wrapped.isClosed }
  override var isFull:   Bool { return wrapped.isFull }
  override func close()  { wrapped.close() }

  override func put(newElement: T) -> Bool { return wrapped.send(newElement) }

  override func selectPut(select: ChannelSemaphore, selection: Selection) { wrapped.selectNotify(select, selection: selection) }
  override func insert(selection: Selection, newElement: T) -> Bool { return wrapped.insert(selection, newElement: newElement) }
}
