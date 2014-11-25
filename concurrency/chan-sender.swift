//
//  chan-sender.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Sender<T> exposes the sending end of a channel.
*/

public class Sender<T>: SenderType
{
  /**
    Return a new Sender<T> to stand in for SendingChannel c.

    If c is a (subclass of) Sender, c will be returned directly.

    If c is any other kind of SenderType, c will be wrapped in a WrappedSender.

    :param: c A SenderType implementor to be wrapped by a Sender object.

    :return:  A Sender object that will pass along the elements to c.
  */

  public class func Wrap<C: SenderType where C.SentElement == T>(c: C) -> Sender<T>
  {
    if let c = c as? Sender<T>
    {
      return c
    }

//    return EnclosedSender(c)
    return WrappedSender(c)
  }

  /**
    Return a new Sender<T> to act as the sending enpoint for a Chan<T>.

    :param: c A Chan<T> object
    :return:  A Sender<T> object that will send elements to the Chan<T>
  */

  class func Wrap(c: Chan<T>) -> Sender<T>
  {
    return ChanSender(c)
  }

  /**
    Return a new Sender<T> to act as the sending enpoint for a ChannelType

    :param: c An object that implements ChannelType
    :return:  A Sender<T> object that will send elements to c
  */

  class func Wrap<C: ChannelType where C.ElementType == T>(c: C) -> Sender<T>
  {
    return ChannelSender(c)
  }

  // Make sure this doesn't get instantiated lightly.

  private init() { }

  // SenderType interface (abstract)

  public var isClosed: Bool { return true }

  public var isFull:  Bool { return false }

  public func close() { }

  public func send(newElement: T)
  {
    _ = newElement
  }
}

/**
  ChanSender<T> wraps a Chan<T> and allows sending through it
  via a SenderType interface.
*/

class ChanSender<T>: Sender<T>
{
  private var wrapped: Chan<T>

  init(_ channel: Chan<T>)
  {
    wrapped = channel
  }

  override var isClosed: Bool { return wrapped.isClosed }

  override var isFull:  Bool { return wrapped.isFull }

  override func close() { wrapped.close() }

  override func send(newElement: T)
  {
    wrapped.put(newElement)
  }
}

/**
  ChannelSender<T,C> wraps a ChannelType (as C) and allows sending through it
  via a SenderType interface.
*/

class ChannelSender<T, C: ChannelType where C.ElementType == T>: Sender<T>
{
  private var wrapped: C

  init(_ channel: C)
  {
    wrapped = channel
  }

  override var isClosed: Bool { return wrapped.isClosed }

  override var isFull:  Bool { return wrapped.isFull }

  override func close() { wrapped.close() }

  override func send(newElement: T)
  {
    wrapped.put(newElement)
  }
}

/**
  EnclosedSender<T> wraps an object that implements SenderType and makes it
  looks like a Sender<T> subclass.

  This is accomplished in wrapping its entire SenderType interface in a series of closures.
  While that is probably memory-heavy, it works. WrappedSender uses a generic approach.
*/

class EnclosedSender<T>: Sender<T>
{
  init<C: SenderType where C.SentElement == T>(_ c: C)
  {
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedWriteFunc = { c.send($0) }
  }

  private var  enclosedGetClosed: () -> Bool
  override var isClosed: Bool { return enclosedGetClosed() }

  private var  enclosedGetFull: () -> Bool
  override var isFull: Bool { return enclosedGetFull() }

  private var  enclosedCloseFunc: () -> ()
  override func close() { enclosedCloseFunc() }

  private var  enclosedWriteFunc: (T) -> ()
  override func send(newElement: T)
  {
    enclosedWriteFunc(newElement)
  }
}

/**
  WrappedSender<T,C> wraps an instance of any type C that implements SenderType,
  and makes it looks like a Sender<T> subclass.

  WrappedSender uses a generic approach, unlike EnclosedSender.
  The choice is probably a matter of larger binary code vs. larger memory use.
*/

class WrappedSender<T, C: SenderType where C.SentElement == T>: Sender<T>
{
  private var wrapped: C

  init(_ channel: C)
  {
    wrapped = channel
  }

  override var isClosed: Bool { return wrapped.isClosed }

  override var isFull:  Bool { return wrapped.isFull }

  override func close() { wrapped.close() }

  override func send(newElement: T)
  {
    wrapped.send(newElement)
  }
}
