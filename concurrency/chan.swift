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

public class Chan<T>: ReceivingChannel, SendingChannel, SelectableChannel
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
        return BufferedQChan<T>(capacity)
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
    Factory function to obtain a Chan<T> wrapper for any implementor of both ReceivingChannel and SendingChannel.

    Why would anyone need this? Perhaps someone implemented a channel quite separately from this library,
    yet needs to be compatible with it.

    :param:  c a channel to wrap

    :return: a newly-wrapped Chan<T> object
  */

  public class func Wrap<C: protocol<ReceivingChannel, SendingChannel>
                         where C.ReceivedElement == T, C.ReceivedElement == C.SentElement>(c: C) -> Chan<T>
  {
    if let c = c as? Chan<T> { return c }

    return EnclosedChan(c)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any ReceivingChannel

    Don't use this. This way lies madness. Your program will deadlock.

    :param:  c a ReceivingChannel implementor to wrap

    :return: a newly-wrapped Chan<T> object
  */

  class func Wrap<C: ReceivingChannel where C.ReceivedElement == T>(c: C) -> Chan<T>
  {
    return EnclosedDirectionalChan(c)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any SendingChannel

    Don't use this. This way lies madness. Your program will deadlock.

    :param:  c a SendingChannel implementor to wrap

    :return: a newly-wrapped Chan<T> object
  */

  class func Wrap<C: SendingChannel where C.SentElement == T>(c: C) -> Chan<T>
  {
    return EnclosedDirectionalChan(c)
  }

  // Computed properties

  /**
    Determine whether the channel is empty (and therefore can't be received from)
  */

  final public var isEmpty: Bool { return isEmptyFunc() }

  func isEmptyFunc() -> Bool { return true }

  /**
    Determine whether the channel is full (and can't be written to)
  */

  final public var isFull: Bool { return isFullFunc() }

  func isFullFunc() -> Bool { return false }
  
  /**
    Report the channel capacity
  */

  final public var capacity: Int { return capacityFunc() }

  func capacityFunc() -> Int { return 0 }

  /**
    Determine whether the channel has been closed
  */

  final public var isClosed: Bool { return isClosedFunc() }

  func isClosedFunc() -> Bool { return true }

  // BasicChannel, SendingChannel and ReceivingChannel methods.

  /**
    Close the channel
  
    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  public func close() { }

  /**
    Send a new element to the channel
  
    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  public func send(newElement: T)
  {
    _ = newElement
  }

  /**
    Receive the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  public func receive() -> T?
  {
    return nil
  }

  // Methods for Selectable

  public var invalidSelection: Bool { return isClosed && isEmpty }

  public func selectReceive(channel: SelectChan<Selection>, messageID: Selectable) -> Signal
  {
    channel.selectMutex {
      channel.selectSend(Selection(messageID: messageID, messageData: (nil as T?)))
    }

    return {}
  }

  // Method for SelectableChannel

  public func extract(selection: Selection) -> T?
  {
    let data = selection.data
    if data is T?
    {
      return data as T?
    }

    return nil
  }
}

extension Chan: GeneratorType
{
  /**
    Return the next element from the channel.
    This is an alias for Chan<T>.receive() and fulfills the GeneratorType protocol.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  public func next() -> T?
  {
    return receive()
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
  Wrap an object that implements both ReceivingChannel and SendingChannel (for element type T)
  in something than will look like a Chan<T>.

  Even though the object may not be a Chan<T>, this is accomplished in wrapping its
  entire ReceivingChannel and SendingChannel interfaces in a series of closures.
  It's probably memory-heavy, but it's pretty nice that it can be done...
*/

private class EnclosedChan<T>: Chan<T>
{
  private init<C: protocol<ReceivingChannel,SendingChannel>
               where C.ReceivedElement == T, C.ReceivedElement == C.SentElement>(_ c: C)
  {
    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedSendFunc =  { c.send($0) }

    enclosedGetEmpty =    { c.isEmpty }
    enclosedReceiveFunc = { c.receive() }

//    enclosedIsSelectable =  { c.invalidSelection }
//    enclosedSelectReceive = { c.selectReceive($0, messageID: $1) }
//    enclosedExtractFunc =   { c.extract($0) }
}

  private override init()
  {
    enclosedCapacity =  { 0 }
    enclosedGetClosed = { true }
    enclosedCloseFunc = { }

    enclosedGetFull =   { true }
    enclosedSendFunc =  { _ = $0 }

    enclosedGetEmpty =  { true }
    enclosedReceiveFunc =  { nil }

//    enclosedIsSelectable =  { false }
//    enclosedSelectReceive = { _ = $0; _ = $1; {} }
//    enclosedExtractFunc =   {
//      (a: Selection?) -> T? in
//      nil as T?
//    }
  }

  private var  enclosedCapacity: () -> Int
//  override var capacity: Int { return enclosedCapacity() }
  override func capacityFunc() -> Int { return enclosedCapacity() }

  private var  enclosedGetClosed: () -> Bool
//  override var isClosed: Bool { return enclosedGetClosed() }
  override func isClosedFunc() -> Bool { return enclosedGetClosed() }

  private var  enclosedCloseFunc: () -> ()
  override func close() { enclosedCloseFunc() }

  private var  enclosedGetFull: () -> Bool
//  override var isFull: Bool { return enclosedGetFull() }
  override func isFullFunc() -> Bool { return enclosedGetFull() }

  private var  enclosedSendFunc: (T) -> ()
  override func send(newElement: T)
  {
    enclosedSendFunc(newElement)
  }

  private var  enclosedGetEmpty: () -> Bool
//  override var isEmpty: Bool { return enclosedGetEmpty() }
  override func isEmptyFunc() -> Bool { return enclosedGetEmpty() }

  private var  enclosedReceiveFunc: () -> T?
  override func receive() -> T?
  {
    return enclosedReceiveFunc()
  }

//  private var enclosedIsSelectable: () -> Bool
//  override var invalidSelection: Bool { return enclosedIsSelectable() }

//  private var enclosedSelectReceive: (SelectChan<Selection>, Selectable) -> Signal
//  override func selectReceive(channel: SelectChan<Selection>, messageID: Selectable) -> Signal
//  {
//    return enclosedSelectReceive(channel, messageID)
//  }

//  private var enclosedExtractFunc: (Selection?) -> T?
//  override func extract(selection: Selection?) -> T?
//  {
//    return enclosedExtractFunc(selection)
//  }
}

/**
  A wrapper for a an implementor of ReceivingChannel or SendingChannel, but not both.
  It wraps said implementor inside something that appears to implement protocols.

  This way lies madness. Do not use this. Deadlocks will happen.
*/

private class EnclosedDirectionalChan<T>: EnclosedChan<T>
{
  private override init<C: ReceivingChannel where C.ReceivedElement == T>(_ c: C)
  {
    super.init()

    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { true }
    enclosedSendFunc =  { _ = $0 }

    enclosedGetEmpty =  { c.isEmpty }
    enclosedReceiveFunc =  { c.receive() }
  }

  private override init<C: SendingChannel where C.SentElement == T>(_ c: C)
  {
    super.init()

    enclosedCapacity =  { c.capacity }
    enclosedGetClosed = { c.isClosed }
    enclosedCloseFunc = { c.close() }

    enclosedGetFull =   { c.isFull }
    enclosedSendFunc =  { c.send($0) }

    enclosedGetEmpty =  { true }
    enclosedReceiveFunc =  { nil }
  }
}


