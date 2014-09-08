//
//  chan-directional.swift
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

public class ReadChan<T>: ReceivingChannel, SelectableChannel, GeneratorType, SequenceType
{
  /**
    Return a new ReadChan<T> to stand in for ReceivingChannel c.

    If c is a (subclass of) ReadChan, c will be returned directly.
    If c is a Chan, c will be wrapped in a new WrappedReadChan

    If c is any other kind of ReceivingChannel, c will be wrapped in an
    EnclosedReadChan, which uses closures to wrap the interface of c.

    :param: c A ReceivingChannel implementor to be wrapped by a ReadChan object.
  
    :return:  A ReadChan object that will pass along the elements from c.
  */

  public class func Wrap<C: SelectableChannel where C.ReceivedElement == T>(c: C) -> ReadChan<T>
  {
    if let c = c as? ReadChan<T> { return c }
    if let c = c as? Chan<T>     { return WrappedReadChan(c) }

    return EnclosedReadChan(c)
  }

  // ReceivingChannel interface (abstract)

  public var capacity: Int  { return 0 }
  public var isClosed: Bool { return true }

  public var isEmpty:  Bool { return false }

  public func close() { }

  public func receive() -> T?
  {
    return nil
  }

  // SelectableChannel interface (abstract)

  public var invalidSelection: Bool { return isClosed && isEmpty }

  public func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    channel.selectMutex {
      channel.selectSend(Selection(messageID: messageID, messageData: (nil as T?)))
    }

    return {}
  }

  public func extract(selection: SelectionType?) -> T?
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
  WrappedReadChan<T> wraps a Chan<T> and effectively hides its
  SendingChannel implementation, effectively making the channel one-way only.
*/

class WrappedReadChan<T>: ReadChan<T>
{
  private var wrapped: Chan<T>

  init(_ c: Chan<T>)
  {
    wrapped = c
  }

  // ReceivingChannel implementation

  override var capacity: Int  { return wrapped.capacity }
  override var isClosed: Bool { return wrapped.isClosed }

  override var isEmpty:  Bool { return wrapped.isEmpty }

  override func close() { wrapped.close() }

  override func receive() -> T?
  {
    return wrapped.receive()
  }

  // SelectableChannel implementation

  override var invalidSelection: Bool { return wrapped.invalidSelection }

  override func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return wrapped.selectReceive(channel, messageID: messageID)
  }

  override func extract(selection: SelectionType?) -> T?
  {
    return wrapped.extract(selection)
  }
}

/**
  EnclosedReadChan<T> wraps an object that implements SelectableChannel and makes it
  looks like a ReadChan<T> subclass.

  This is accomplished in wrapping its entire ReceivingChannel interface in a series of closures.
  It's probably memory-heavy, but it can be done, and it works.
*/

class EnclosedReadChan<T>: ReadChan<T>
{
  init<C: SelectableChannel where C.ReceivedElement == T>(_ c: C)
  {
    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetEmpty =    { c.isEmpty }
    enclosedReceiveFunc = { c.receive() }

    enclosedIsSelectable =  { c.invalidSelection }
    enclosedSelectReceive = { c.selectReceive($0, messageID: $1) }
    enclosedExtractFunc =   { c.extract($0) }
  }

  // ReceivingChannel implementation

  private var  enclosedCapacity: () -> Int
  override var capacity: Int { return enclosedCapacity() }

  private var  enclosedGetClosed: () -> Bool
  override var isClosed: Bool { return enclosedGetClosed() }

  private var  enclosedCloseFunc: () -> ()
  override func close() { enclosedCloseFunc() }

  private var  enclosedGetEmpty: () -> Bool
  override var isEmpty: Bool { return enclosedGetEmpty() }

  private var  enclosedReceiveFunc: () -> T?
  override func receive() -> T?
  {
    return enclosedReceiveFunc()
  }

  private var enclosedIsSelectable: () -> Bool
  override var invalidSelection: Bool { return enclosedIsSelectable() }

  private var enclosedSelectReceive: (SelectChan<SelectionType>, Selectable) -> Signal
  override func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return enclosedSelectReceive(channel, messageID)
  }

  private var enclosedExtractFunc: (SelectionType?) -> T?
  override func extract(selection: SelectionType?) -> T?
  {
    return enclosedExtractFunc(selection)
  }
}

/**
  ReadOnly<C> wraps any implementor of SelectableChannel so that only
  the SelectableChannel interface is available. The type of the wrapped
  SelectableChannel will be visible in the type signature, but it
  will have become a one-way channel.
*/

public class ReadOnly<C: SelectableChannel>: ReceivingChannel, SelectableChannel, GeneratorType, SequenceType
{
  private var wrapped: C

  public init(_ channel: C)
  {
    wrapped = channel
  }

  // ReceivingChannel wrappers

  public var capacity: Int  { return wrapped.capacity }
  public var isClosed: Bool { return wrapped.isClosed }

  public var isEmpty:  Bool { return wrapped.isEmpty }

  public func close() { wrapped.close() }

  public func receive() -> C.ReceivedElement?
  {
    return wrapped.receive()
  }

  // SelectableChannel wrappers

  public var invalidSelection: Bool { return wrapped.invalidSelection }

  public func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return wrapped.selectReceive(channel, messageID: messageID)
  }

  public func extract(item: SelectionType?) -> C.ReceivedElement?
  {
    return wrapped.extract(item)
  }

  // GeneratorType implementation

  public func next() -> C.ReceivedElement?
  {
    return wrapped.receive()
  }

  // SequenceType implementation

  public func generate() -> Self
  {
    return self
  }
}

/**
  WriteChan<T> is a wrapper for a SendingChannel implementor.
  If it had a ReceivingChannel implementation, it becomes inaccessible,
  effectively making it a one-way channel.

  This could be useful to clarify the intentions of an API.
*/

public class WriteChan<T>: SendingChannel
{
  /**
    Return a new WriteChan<T> to stand in for SendingChannel c.

    If c is a (subclass of) WriteChan, c will be returned directly.
    If c is a Chan, c will be wrapped in a new WrappedWriteChan

    If c is any other kind of SendingChannel, c will be wrapped in an
    EnclosedWriteChan, which uses closures to wrap the SendingChannel interface of c.

    :param: c A SendingChannel implementor to be wrapped by a WriteChan object.

    :return:  A WriteChan object that will pass along the elements from c.
  */

  public class func Wrap<C: SendingChannel where C.SentElement == T>(c: C) -> WriteChan<T>
  {
    if let c = c as? WriteChan<T> { return c }
    if let c = c as? Chan<T>     { return WrappedWriteChan(c) }

    return EnclosedWriteChan(c)
  }


  // SendingChannel interface (abstract)

  public var capacity: Int  { return 0 }
  public var isClosed: Bool { return true }

  public var isFull:  Bool { return false }

  public func close() { }

  public func send(newElement: T)
  {
    _ = newElement
  }
}

/**
  WrappedWriteChan<T> wraps a Chan<T> so that only its
  SendingChannel interface is available. The instance
  effectively becomes a one-way channel.
*/

class WrappedWriteChan<T>: WriteChan<T>
{
  private var wrapped: Chan<T>

  init(_ channel: Chan<T>)
  {
    wrapped = channel
  }

  override var capacity: Int  { return wrapped.capacity }
  override var isClosed: Bool { return wrapped.isClosed }

  override var isFull:  Bool { return wrapped.isFull }

  override func close() { wrapped.close() }

  override func send(newElement: T)
  {
    wrapped.send(newElement)
  }
}

/**
  EnclosedWriteChan<T> wraps an object that implements SendingChannel and makes it
  looks like a WriteChan<T> subclass.

  This is accomplished in wrapping its entire SendingChannel interface in a series of closures.
  It's probably memory-heavy, but it can be done, and it works.
*/

class EnclosedWriteChan<T>: WriteChan<T>
{
  init<C: SendingChannel where C.SentElement == T>(_ c: C)
  {
    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedWriteFunc = { c.send($0) }
  }

  private var  enclosedCapacity: () -> Int
  override var capacity: Int { return enclosedCapacity() }

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
  WriteOnly<C> wraps any implementor of SendingChannel so that
  only the SendingChannel interface is available. The type of the wrapped
  SendingChannel will be visible in the type signature, but it
  will have become a one-way channel.
*/

public class WriteOnly<C: SendingChannel>: SendingChannel
{
  private var wrapped: C

  public init(_ channel: C)
  {
    wrapped = channel
  }

  public var capacity: Int  { return wrapped.capacity }
  public var isClosed: Bool { return wrapped.isClosed }

  public var isFull:  Bool { return wrapped.isFull }

  public func close() { wrapped.close() }

  public func send(newElement: C.SentElement)
  {
    wrapped.send(newElement)
  }
}

