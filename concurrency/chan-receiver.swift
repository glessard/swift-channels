//
//  chan-receiver.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Receiver<T> is the receiving endpoint for a ChannelType.
*/

extension Receiver
{
  /**
    Return a new Receiver<T> to act as the receiving endpoint for a Chan<T>.

    :param: c A Chan<T> object
    :return:  A Receiver<T> object that will receive elements from the Chan<T>
  */

  public class func Wrap(c: Chan<T>) -> Receiver<T>
  {
    return Receiver(c)
  }

  /**
    Return a new Receiver<T> to act as the receiving endpoint for a ChannelType.

    :param: c An object that implements ChannelType
    :return:  A Receiver<T> object that will receive elements from the ChannelType
  */

  class func Wrap<C: ChannelType where C.Element == T>(c: C) -> Receiver<T>
  {
    if let chan = c as? Chan<T>
    {
      return Receiver(chan)
    }

    return Receiver(ChannelTypeAsChan(c))
  }

  /**
    Return a new Receiver<T> to stand in for ReceiverType c.

    If c is a Receiver, c will be returned directly.

    If c is any other kind of ReceiverType, c will be type-obscured and
    wrapped in a new Receiver.

    :param: c An object that implements ReceiverType.
    :return:  A Receiver object that will pass along the elements from c.
  */

  public class func Wrap<C: ReceiverType where C.ReceivedElement == T>(c: C) -> Receiver<T>
  {
    if let r = c as? Receiver<T>
    {
      return r
    }

    return Receiver(ReceiverTypeAsChan(c))
  }
}

/**
  Receiver<T> is the receiving endpoint for a ChannelType.
*/

public final class Receiver<T>: ReceiverType, GeneratorType, SequenceType, Selectable
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

  // ReceiverType implementation

  public var isClosed: Bool { return wrapped.isClosed }
  public var isEmpty:  Bool { return wrapped.isEmpty }
  public func close()  { wrapped.close() }

  public func receive() -> T?
  {
    return wrapped.get()
  }

  // GeneratorType implementation

  /**
    If all elements are exhausted, return `nil`.  Otherwise, advance
    to the next element and return it.
    This is a synonym for receive()
  */

  public func next() -> T?
  {
    return wrapped.get()
  }

  // SequenceType implementation

  public func generate() -> Self
  {
    return self
  }

  // Selectable implementation

  public func selectNotify(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    return wrapped.selectGet(semaphore, selectionID: selectionID)
  }

  public func selectNow(selectionID: Selectable) -> Selection?
  {
    return wrapped.selectGetNow(selectionID)
  }

  public var selectable: Bool
  {
    return !(wrapped.isClosed && wrapped.isEmpty)
  }

  // A utility for SelectableChannelType, in place of a better idea

  public func extract(selection: Selection) -> T?
  {
    precondition(selection.id === self, __FUNCTION__)
    return selection.getData()
  }
}

/**
  Channel receive operator: receive the oldest element from the channel.

  If the channel is empty, this call will block.
  If the channel is empty and closed, this will return nil.

  This is the equivalent of Receiver<T>.receive() -> T?

  :param:  r a ReceiverType

  :return: the oldest element from the channel
*/

public prefix func <-<T>(r: Receiver<T>) -> T?
{
  return r.wrapped.get()
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
