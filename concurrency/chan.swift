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

public class Chan<T>: ReadableChannel, WritableChannel
{
  /**
    Factory function to obtain a new, unbuffered Chan<T> object (channel capacity = 0).

    :return: a newly-created, empty, unbuffered Chan<T> object.
  */

  public class func Make() -> Chan<T>
  {
    return UnbufferedChan<T>()
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
        return Buffered1Chan<T>(1)

      default:
        return Buffered1Chan<T>(capacity) // BufferedNChannel<T>(capacity)
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

  internal class func Wrap<C: ReadableChannel where C.ReadElement == T>(c: C) -> Chan<T>
  {
    return EnclosedDirectionalChan(c)
  }

  /**
    Factory function to obtain a Chan<T> wrapper for any WritableChannel

    Don't use this. This way lies madness. Your program will deadlock.

    :param:  c a WritableChannel implementor to wrap

    :return: a newly-wrapped Chan<T> object
  */

  internal class func Wrap<C: WritableChannel where C.WrittenElement == T>(c: C) -> Chan<T>
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

private class EnclosedDirectionalChan<T>: EnclosedChan<T>
{
  // Bug-prone! Don't use this

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

  // Bug-prone! Don't use this

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

/**
  The basis for our concrete channels
*/

private class ConcreteChan<T>: Chan<T>
{
  // Instance variables

  private var closed = false

  private var channelMutex:   UnsafeMutablePointer<pthread_mutex_t>
  private var readCondition:  UnsafeMutablePointer<pthread_cond_t>
  private var writeCondition: UnsafeMutablePointer<pthread_cond_t>

  // Initialization and destruction

  private override init()
  {
    channelMutex = UnsafeMutablePointer<pthread_mutex_t>.alloc(1)
    pthread_mutex_init(channelMutex, nil)

    writeCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(writeCondition, nil)

    readCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(readCondition, nil)

    closed = false
  }

  deinit
  {
    pthread_mutex_destroy(channelMutex)
    channelMutex.dealloc(1)

    pthread_cond_destroy(readCondition)
    readCondition.dealloc(1)

    pthread_cond_destroy(writeCondition)
    writeCondition.dealloc(1)
  }

  // Computed properties

  /**
    Determine whether the channel is empty (and therefore can't be read from)
  */

  private override var isEmpty: Bool { return false }

  /**
    Determine whether the channel is full (and can't be written to)
  */

  private override var isFull: Bool { return false }

  /**
    Report the channel capacity
  */

  private override var capacity: Int { return 0 }

  /**
    Determine whether the channel has been closed
  */

  private override var isClosed: Bool { return closed }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  private override func close()
  {
    pthread_mutex_lock(channelMutex)

    self.closed = true

    // Unblock the threads waiting on our conditions.
    pthread_cond_signal(readCondition)
    pthread_cond_signal(writeCondition)
    pthread_mutex_unlock(channelMutex)
  }

  /**
    Write a new element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  private override func write(newElement: T)
  {
    _ = newElement
  }

  /**
    Read the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  private override func read() -> T?
  { // If we return 'nil', we should set the channel state to 'closed'
    close()
    return nil
  }
}

/**
  A buffered channel.
*/

private class BufferedChan<T>: ConcreteChan<T>
{
  private let channelCapacity: Int = 0

  private init(var _ capacity: Int)
  {
    if capacity < 1 { capacity = 1 }

    channelCapacity = capacity
    super.init()
  }

  private convenience override init()
  {
    self.init(1)
  }

  private let logging = false
  private func log(message: String) -> ()
  {
    if logging { syncprint(message) }
  }

  private override var capacity: Int { return channelCapacity }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It should perhaps be considered an error to close a channel that has
    already been closed, but in fact nothing will happen if it were to occur.
  */

  private override func close()
  {
    if closed { return }

//    log("closing buffered channel")
    super.close()
  }
  
  /**
    Append an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  private override func write(newElement: T)
  {
    if self.closed { return }

    pthread_mutex_lock(channelMutex)

//    log("attempting to write to buffered channel")

    while self.isFull && !self.closed
    { // wait while the channel is full
      pthread_cond_wait(writeCondition, channelMutex)
    }

    // If Channel is closed, we could get here while
    // the queue is "full". Don't overflow.
    if !self.isFull { writeElement(newElement) }

    // Channel is not empty; signal this.
    pthread_cond_signal(readCondition)
    if self.closed { pthread_cond_signal(writeCondition) }
    pthread_mutex_unlock(channelMutex)

//    log("wrote to buffered channel")
  }

  private func writeElement(newElement: T)
  {
    _ = newElement
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  private override func read() -> T?
  {
    pthread_mutex_lock(channelMutex)

//    log("attempting to read from buffered channel")

    while self.isEmpty && !self.closed
    { // block while the channel is empty
      pthread_cond_wait(readCondition, channelMutex)
    }

    let oldElement = readElement()

    // Channel is not full; signal this.
    pthread_cond_signal(writeCondition)
    if self.closed { pthread_cond_signal(readCondition) }
    pthread_mutex_unlock(channelMutex)

//    log("read from buffered channel")

    return oldElement
  }

  private func readElement() ->T?
  {
    return nil
  }
}


/**
  A buffered channel.
*/

private class BufferedNChan<T>: BufferedChan<T>
{
  private var q: Queue<T>

  private override init(var _ capacity: Int)
  {
    if capacity < 1 { capacity = 1 }

    self.q = Queue<T>()
    super.init(capacity)
  }

  private convenience init()
  {
    self.init(1)
  }

  private override var isEmpty: Bool { return q.isEmpty }

  private override var isFull: Bool { return q.count >= capacity }

  private override func writeElement(newElement: T)
  {
    q.enqueue(newElement)
  }

  private override func readElement() ->T?
  {
    return q.dequeue()
  }
}

/**
  A buffered channel with a one-element backing store.
*/

private class Buffered1Chan<T>: BufferedChan<T>
{
  private var element: T? = nil

  private override init(var _ capacity: Int)
  {
    capacity = 1
    element = nil
    super.init(capacity)
  }

  private convenience init()
  {
    self.init(1)
  }

  private override var isEmpty: Bool { return (element == nil) }

  private override var isFull: Bool  { return (element != nil) }

  private override func writeElement(newElement: T)
  {
    element = newElement
  }

  private override func readElement() ->T?
  {
    let oldElement = self.element
    self.element = nil
    return oldElement
  }
}

/**
  A channel with no backing store. Write operations block until a receiver is ready, while
  conversely read operations block until a sender is ready.
*/

private class UnbufferedChan<T>: ConcreteChan<T>
{
  private var element: T? = nil
  private var blockedReaders = 0
  private var blockedWriters = 0

  private override init()
  {
    element = nil
    blockedReaders = 0
    blockedWriters = 0
    super.init()
  }

  private convenience init(capacity: Int)
  {
    self.init()
  }

  private override var isEmpty: Bool { return (element == nil) }

  private override var isFull: Bool  { return (element != nil) }

  private override var capacity: Int { return 0 }

  private let logging = false
  private func log(message: String) -> ()
  {
    if logging { syncprint(message) }
  }

  /**
  Close the channel

  Any items still in the channel remain and can be retrieved.
  New items cannot be added to a closed channel.

  It should perhaps be considered an error to close a channel that has
  already been closed, but in fact nothing will happen if it were to occur.
  */

  private override func close()
  {
    if closed { return }

//    log("closing 0-channel")
    super.close()
  }
  
  /**
    Write an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  private override func write(newElement: T)
  {
    if self.closed { return }

    pthread_mutex_lock(channelMutex)

//    log("attempting to write to 0-channel")

    while ( blockedReaders == 0 || !self.isEmpty ) && !self.closed
    {
      blockedWriters += 1
       // wait while no reader is ready.
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    assert(self.isEmpty || self.closed, "Messed up an unbuffered write")

    self.element = newElement

    // Surely we can interest a reader
    assert(blockedReaders > 0 || self.closed, "No reader available!")
    pthread_cond_signal(readCondition)
    if self.closed { pthread_cond_signal(writeCondition) }
    pthread_mutex_unlock(channelMutex)

//    log("wrote to 0-channel")
  }

  /**
    Read an element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  private override func read() -> T?
  {
    pthread_mutex_lock(channelMutex)

//    log("attempting to read from 0-channel")

    while self.isEmpty && !self.closed
    {
      blockedReaders += 1
      if blockedWriters > 0
      {
        // Maybe we can interest a writer
        pthread_cond_signal(writeCondition)
      }
      // wait for a writer to signal us
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    assert(!self.isEmpty || self.isClosed, "Messed up an unbuffered read")

    let element = self.element
    self.element = nil

    if self.closed { pthread_cond_signal(readCondition) }
    pthread_mutex_unlock(channelMutex)

//    log("read from 0-channel")

    return element
  }
}
