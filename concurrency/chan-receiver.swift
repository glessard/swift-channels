//
//  chan-receiver.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  ReadChan<T> is a wrapper for a SelectableChannel implementor.
  If it had a SendingChannel implementation, it becomes inaccessible,
  effectively making the channel one-way only.

  This could be useful to clarify the intentions of an API.
*/

public class Receiver<T>: ReceiverType, GeneratorType, SequenceType
{
  /**
    Return a new Receiver<T> to stand in for ReceiverType c.

    If c is a (subclass of) Receiver, c will be returned directly.

    If c is any other kind of ReceiverType, c will be wrapped in a
    WrappedReceiver, a generic wrapper for ReceiverTypes.

    :param: c A ReceiverType implementor to be wrapped by a Receiver object.
  
    :return:  A Receiver object that will pass along the elements from c.
  */

  public class func Wrap<C: ReceiverType where C.ReceivedElement == T>(c: C) -> Receiver<T>
  {
    if let c = c as? Receiver<T>
    {
      return c
    }

    return WrappedReceiver(c)
  }

  /**
    Return a new Receiver<T> to act as the receiving enpoint for a Chan<T>.
  
    :param: c A Chan<T> object
    :return:  A Receiver<T> object that will receive elements from the Chan<T>
  */

  class func Wrap(c: Chan<T>) -> Receiver<T>
  {
    return ChanReceiver(c)
  }

  /**
    Return a new Receiver<T> to act as the receiving enpoint for a ChannelType.

    :param: c A object that implements ChannelType
    :return:  A Receiver<T> object that will receive elements from c
  */

  class func Wrap<C: ChannelType where C.ElementType == T>(c: C) -> Receiver<T>
  {
    return ChannelReceiver(c)
  }

  // Make sure this doesn't get instantiated lightly.

  private init() { }

  // ReceiverType interface (abstract)

  public var isClosed: Bool { return true }

  public var isEmpty:  Bool { return false }

  public func close() { }

  public func receive() -> T?
  {
    return nil
  }

  // GeneratorType implementation

  /**
    If all elements are exhausted, return `nil`.  Otherwise, advance
    to the next element and return it.
  */

  public func next() -> T?
  {
    return receive()
  }

  // SequenceType implementation

  public func generate() -> Self
  {
    return self
  }
}

/**
  ChanReceiver<T> wraps a Chan<T> to become its receiving endpoint.
*/

class ChanReceiver<T>: Receiver<T>
{
  private var wrapped: Chan<T>

  init(_ c: Chan<T>)
  {
    wrapped = c
  }

  // ReceiverType implementation

  override var isClosed: Bool { return wrapped.isClosed }

  override var isEmpty:  Bool { return wrapped.isEmpty }

  override func close() { wrapped.close() }

  override func receive() -> T?
  {
    return wrapped.take()
  }
}

/**
  ChannelReceiver<T> wraps a ChannelType to become its receiving endpoint.
*/

class ChannelReceiver<T, C: ChannelType where C.ElementType == T>: Receiver<T>
{
  private var wrapped: C

  init(_ c: C)
  {
    wrapped = c
  }

  // ReceiverType implementation

  override var isClosed: Bool { return wrapped.isClosed }

  override var isEmpty:  Bool { return wrapped.isEmpty }

  override func close() { wrapped.close() }

  override func receive() -> T?
  {
    return wrapped.take()
  }
}

/**
  WrappedReceiver<T,C> wraps an instance of any type C that implements ReceiverType,
  and makes it look like a subclass of Receiver<T>.
*/

class WrappedReceiver<T, C: ReceiverType where C.ReceivedElement == T>: Receiver<T>
{
  private var wrapped: C

  init(_ receiver: C)
  {
    wrapped = receiver
  }

  // ReceiverType wrappers

  override var isClosed: Bool { return wrapped.isClosed }

  override var isEmpty:  Bool { return wrapped.isEmpty }

  override func close() { wrapped.close() }

  override func receive() -> T?
  {
    return wrapped.receive()
  }

//  // SelectableChannel wrappers
//
//  public var invalidSelection: Bool { return wrapped.invalidSelection }
//
//  public func selectReceive(channel: SelectChan<Selection>, messageID: Selectable) -> Signal
//  {
//    return wrapped.selectReceive(channel, messageID: messageID)
//  }
//
//  public func extract(item: Selection) -> C.ReceivedElement?
//  {
//    return wrapped.extract(item)
//  }
}
