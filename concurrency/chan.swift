//
//  chan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A channel allows concurrently executing tasks to communicate by sending and
  receiving data of a specific type.

  The factory class function Make(capacity: Int) returns a Chan instance that is buffered
  (if capacity > 0), or unbuffered (if capacity is 0). The no-parameter version
  of the factory function returns an unbuffered channel.
*/

public class Chan<T>: ReadableChannel, WritableChannel, SelectableChannel
{
  /**
    Factory function to obtain a new, unbuffered Chan<T> object (channel capacity = 0).

    :return: a newly-created, empty, unbuffered Chan<T> object.
  */

  public class func Make() -> Chan<T>
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new Chan<T> object.
  
    :param: capacity the buffer capacity of the channel. If capacity is 0, then an unbuffered channel will be created.
  
    :return: a newly-created, empty Chan<T> object.
  */

  public class func Make(capacity: Int) -> Chan<T>
  {
    switch capacity
    {
      case let c where c < 1:
        return UnbufferedChan<T>()
      case 1:
        return Buffered1Chan<T>()

      default:
        return Buffered1Chan<T>() // BufferedNChannel<T>(capacity)
    }
  }

  /**
    Factory function to obtain a new Chan<T> object, using a sample element to determine the type.

    :param: type a sample object whose type will be used for the channel's element type. The object is not retained.
    :param: capacity the buffer capacity of the channel. Default is 0, meaning an unbuffered channel.

    :return: a newly-created, empty, Chan<T> object
  */

  public class func Make(#type: T, _ capacity: Int = 0) -> Chan<T>
  {
    return Make(capacity)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any implementor of protocol<ReadableChannel, WritableChannel>.

    Why would anyone need this? Perhaps someone implemented a channel quite separately from this library,
    yet needs to be compatible with it.

    :param:  c a channel to wrap

    :return: a newly-wrapped Chan<T> object
  */

  public class func Wrap<C: protocol<ReadableChannel, WritableChannel>
                         where C.ReadElement == T, C.ReadElement == C.WrittenElement>(c: C) -> Chan<T>
  {
    if let c = c as? Chan<T> { return c }

    return EnclosedChan(c)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any ReadableChannel

    Don't use this. This way lies madness. Your program will deadlock.

    :param:  c a ReadableChannel implementor to wrap

    :return: a newly-wrapped Chan<T> object
  */

  class func Wrap<C: ReadableChannel where C.ReadElement == T>(c: C) -> Chan<T>
  {
    return EnclosedDirectionalChan(c)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any WritableChannel

    Don't use this. This way lies madness. Your program will deadlock.

    :param:  c a WritableChannel implementor to wrap

    :return: a newly-wrapped Chan<T> object
  */

  class func Wrap<C: WritableChannel where C.WrittenElement == T>(c: C) -> Chan<T>
  {
    return EnclosedDirectionalChan(c)
  }

  // Computed properties

  /**
    Determine whether the channel is empty (and therefore can't be read from)
  */

  public var isEmpty: Bool { return false }

  /**
    Determine whether the channel is full (and can't be written to)
  */

  public var isFull: Bool { return false }
  
  /**
    Report the channel capacity
  */

  public var capacity: Int { return 0 }

  /**
    Determine whether the channel has been closed
  */

  public var isClosed: Bool { return true }

  /**
    Close the channel
  
    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  public func close() { }

  /**
    Write a new element to the channel
  
    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  public func write(newElement: T)
  {
    _ = newElement
  }

  /**
    Read the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  public func read() -> T?
  {
    return nil
  }

  // Methods for Selectable

  public var invalidSelection: Bool { return isClosed && isEmpty }

  public func selectRead(channel: SelectChan<Selectable>, message: Selectable) -> Signal
  {
    // The compiler is demanding this by claiming that 'isClosed' below is ambiguous.
    let disambiguatedChannel: Chan<Selectable> = channel

    channel.channelMutex {
      if disambiguatedChannel.isClosed == false
      {
        let nilT: T? = nil
        channel.stash = SelectPayload(payload: nilT)
        channel.writeElement(message)
      }
    }

    return Signal( {} )
  }

  // Method for SelectableChannel

  public func extract(item: Selectee?) -> T?
  {
    if item != nil
    {
      if let item = item as? SelectPayload<T>
      {
        return item.data
      }
    }
    return nil
  }
}

extension Chan: GeneratorType
{
  /**
    Return the next element from the channel.
    This is an alias for Chan<T>.read() and fulfills the GeneratorType protocol.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  public func next() -> T?
  {
    return read()
  }
}

extension Chan: SequenceType
{
  /**
    Return self as GeneratorType to be used by a for loop.
    This fulfills the SequenceType protocol.
  
    :return: an implementor of GeneratorType to iterate along the channel's elements.
  */

  public func generate() -> Self
  {
    return self
  }
}

/**
  Wrap an object that implements both ReadableChannel and WritableChannel (for element type T)
  in something than will look like a Chan<T>.

  Even though the object may not be a Chan<T>, this is accomplish in wrapping its entire interface
  in a series of closures. It's probably memory-heavy, but it's pretty nice that it can be done...
*/

private class EnclosedChan<T>: Chan<T>
{
  private init<C: protocol<ReadableChannel,WritableChannel> where C.ReadElement == T, C.ReadElement == C.WrittenElement>(_ c: C)
  {
    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedWriteFunc = { c.write($0) }

    enclosedGetEmpty =  { c.isEmpty }
    enclosedReadFunc =  { c.read() }
  }

  private override init()
  {
    enclosedCapacity =  { 0 }
    enclosedGetClosed = { true }
    enclosedCloseFunc = { }

    enclosedGetFull =   { true }
    enclosedWriteFunc = { _ = $0 }

    enclosedGetEmpty =  { true }
    enclosedReadFunc =  { nil }
  }

  private var  enclosedCapacity: () -> Int
  override var capacity: Int { return enclosedCapacity() }

  private var  enclosedGetClosed: () -> Bool
  override var isClosed: Bool { return enclosedGetClosed() }

  private var  enclosedCloseFunc: () -> ()
  override func close() { enclosedCloseFunc() }

  private var  enclosedGetFull: () -> Bool
  override var isFull: Bool { return enclosedGetFull() }

  private var  enclosedWriteFunc: (T) -> ()
  override func write(newElement: T)
  {
    enclosedWriteFunc(newElement)
  }

  private var  enclosedGetEmpty: () -> Bool
  override var isEmpty: Bool { return enclosedGetEmpty() }

  private var  enclosedReadFunc: () -> T?
  override func read() -> T?
  {
    return enclosedReadFunc()
  }
}

/**
  A wrapper for a an implementor of ReadableChannel or WritableChannel, but not both.
  It wraps said implementor inside something that appears to implement protocols.

  This way lies madness. Do not use this. Deadlocks will happen.
*/

private class EnclosedDirectionalChan<T>: EnclosedChan<T>
{
  private override init<C: ReadableChannel where C.ReadElement == T>(_ c: C)
  {
    super.init()

    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { true }
    enclosedWriteFunc = { _ = $0 }

    enclosedGetEmpty =  { c.isEmpty }
    enclosedReadFunc =  { c.read() }
  }

  private override init<C: WritableChannel where C.WrittenElement == T>(_ c: C)
  {
    super.init()

    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedWriteFunc = { c.write($0) }

    enclosedGetEmpty =  { true }
    enclosedReadFunc =  { nil }
  }
}


