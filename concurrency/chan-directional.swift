//
//  chan-directional.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-23.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  ReadChan<T> wraps a ReadableChannel implementor in a concrete class.
*/

public class ReadChan<T>: ReadableChannel, SelectableChannel, GeneratorType, SequenceType
{
  /**
    Return a new ReadChan<T> to stand in for ReadableChannel c.

    If c is a (subclass of) ReadChan, c will be returned directly.
    If c is a Chan, c will be wrapped in a new WrappedReadChan

    If c is any other kind of ReadableChannel, c will be wrapped in an
    EnclosedReadChan, which uses closures to wrap the interface of c.

    :param: c A ReadableChannel implementor to be wrapped by a ReadChan object.
  
    :return:  A ReadChan object that will pass along the elements from c.
  */

  public class func Wrap<C: SelectableChannel where C.ReadElement == T>(c: C) -> ReadChan<T>
  {
    if let c = c as? ReadChan<T> { return c }
    if let c = c as? Chan<T>     { return WrappedReadChan(c) }

    return EnclosedReadChan(c)
  }

  // ReadableChannel interface

  public var capacity: Int  { return 0 }
  public var isClosed: Bool { return true }

  public var isEmpty:  Bool { return false }

  public func close() { }

  public func read() -> T?
  {
    return nil
  }

  // SelectableChannel interface
  
  public var invalidSelection: Bool { return isClosed && isEmpty }

  public func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    assert(false, "This placeholder function should never execute!")
    return { }
  }

  public func extract(selection: SelectionType?) -> T?
  {
    if selection != nil
    {
      if let selection = selection as? Selection<T>
      {
        return selection.data
      }
    }
    return nil
  }

  // GeneratorType implementation

  /**
    If all elements are exhausted, return `nil`.  Otherwise, advance
    to the next element and return it.
  */

  public func next() -> T?
  {
    return read()
  }

  // SequenceType implementation

  public func generate() -> Self
  {
    return self
  }
}

class WrappedReadChan<T>: ReadChan<T>
{
  private var wrapped: Chan<T>

  init(_ c: Chan<T>)
  {
    wrapped = c
  }

  // ReadableChannel implementation

  override var capacity: Int  { return wrapped.capacity }
  override var isClosed: Bool { return wrapped.isClosed }

  override var isEmpty:  Bool { return wrapped.isEmpty }

  override func close() { wrapped.close() }

  override func read() -> T?
  {
    return wrapped.read()
  }

  override var invalidSelection: Bool { return wrapped.invalidSelection }

  override func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return wrapped.selectRead(channel, messageID: messageID)
  }
}

/**

*/

class EnclosedReadChan<T>: ReadChan<T>
{
  init<C: SelectableChannel where C.ReadElement == T>(_ c: C)
  {
    enclosedCapacity =   { c.capacity }
    enclosedGetClosed =  { c.isClosed }
    enclosedCloseFunc =  { c.close() }

    enclosedGetEmpty =   { c.isEmpty }
    enclosedReadFunc =   { c.read() }

    enclosedSelectGo =   { c.invalidSelection }
    enclosedSelectRead = { c.selectRead($0, messageID: $1) }
  }

  // ReadableChannel implementation

  private var  enclosedCapacity: () -> Int
  override var capacity: Int { return enclosedCapacity() }

  private var  enclosedGetClosed: () -> Bool
  override var isClosed: Bool { return enclosedGetClosed() }

  private var  enclosedCloseFunc: () -> ()
  override func close() { enclosedCloseFunc() }

  private var  enclosedGetEmpty: () -> Bool
  override var isEmpty: Bool { return enclosedGetEmpty() }

  private var  enclosedReadFunc: () -> T?
  override func read() -> T?
  {
    return enclosedReadFunc()
  }

  private var enclosedSelectGo: () -> Bool
  override var invalidSelection: Bool { return enclosedSelectGo() }

  private var enclosedSelectRead: (SelectChan<SelectionType>, Selectable) -> Signal
  override func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return enclosedSelectRead(channel, messageID)
  }
}

/**
  ReadOnly<C> wraps any implementor of SelectableChannel so that only
  the SelectableChannel interface is available. The type of the wrapped
  SelectableChannel will be visible in the type signature.
*/

public class ReadOnly<C: SelectableChannel>: ReadableChannel, SelectableChannel, GeneratorType, SequenceType
{
  private var wrapped: C

  public init(_ channel: C)
  {
    wrapped = channel
  }

  public var capacity: Int  { return wrapped.capacity }
  public var isClosed: Bool { return wrapped.isClosed }

  public var isEmpty:  Bool { return wrapped.isEmpty }

  public func close() { wrapped.close() }

  public func read() -> C.ReadElement?
  {
    return wrapped.read()
  }

  public func next() -> C.ReadElement?
  {
    return wrapped.read()
  }

  public func generate() -> Self
  {
    return self
  }

  public var invalidSelection: Bool { return wrapped.invalidSelection }

  public func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    return wrapped.selectRead(channel, messageID: messageID)
  }

  public func extract(item: SelectionType?) -> C.ReadElement?
  {
    return wrapped.extract(item)
  }
}

/**
  WriteChan<T> wraps a Chan<T> so that
  only the WritableChannel interface is available.
*/

public class WriteChan<T>: WritableChannel
{
  /**
    Return a new WriteChan<T> to stand in for WritableChannel c.

    If c is a (subclass of) WriteChan, c will be returned directly.
    If c is a Chan, c will be wrapped in a new WrappedWriteChan

    If c is any other kind of WritableChannel, c will be wrapped in an
    EnclosedWriteChan, which uses closures to wrap the interface of c.

    :param: c A WritableChannel implementor to be wrapped by a WriteChan object.

    :return:  A WriteChan object that will pass along the elements from c.
  */

  public class func Wrap<C: WritableChannel where C.WrittenElement == T>(c: C) -> WriteChan<T>
  {
    if let c = c as? WriteChan<T> { return c }
    if let c = c as? Chan<T>     { return WrappedWriteChan(c) }

    return EnclosedWriteChan(c)
  }


  // WritableChannel interface

  public var capacity: Int  { return 0 }
  public var isClosed: Bool { return true }

  public var isFull:  Bool { return false }

  public func close() { }

  public func write(newElement: T)
  {
    _ = newElement
  }
}

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

  override func write(newElement: T)
  {
    wrapped.write(newElement)
  }
}

class EnclosedWriteChan<T>: WriteChan<T>
{
  init<C: WritableChannel where C.WrittenElement == T>(_ c: C)
  {
    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedWriteFunc = { c.write($0) }
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
  override func write(newElement: T)
  {
    enclosedWriteFunc(newElement)
  }
}

/**
  WriteOnly<C> wraps any implementor of WritableChannel so that
  only the WritableChannel interface is available.
*/

public class WriteOnly<C: WritableChannel>: WritableChannel
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

  public func write(newElement: C.WrittenElement)
  {
    wrapped.write(newElement)
  }
}

