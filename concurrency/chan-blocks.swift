//
//  chan-blocks.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

private enum QueueState
{
  case Suspended
  case Running
}

/**
A buffered channel.
*/

class BufferedChan<T>: Chan<T>
{
  private let channelCapacity: Int
  private var closed: Bool = false

  private let mutex:   dispatch_queue_t
  private let readers: dispatch_queue_t
  private let writers: dispatch_queue_t

  private var readerState: QueueState = .Running
  private var writerState: QueueState = .Running

  private init(var _ capacity: Int)
  {
    channelCapacity = (capacity < 0) ? 0 : capacity

    mutex   = dispatch_queue_create("channelmutex", DISPATCH_QUEUE_SERIAL)
    readers = dispatch_queue_create("channelreadq", DISPATCH_QUEUE_SERIAL)
    writers = dispatch_queue_create("channelwritq", DISPATCH_QUEUE_SERIAL)

    super.init()
  }

  // pseudo-keyword shortcuts for Grand Central Dispatch

  func channelMutex(action: () -> ())
  {
    dispatch_sync(mutex)   { action() }
  }

  private func readerMutex(action: () -> ())
  {
    dispatch_sync(readers) { action() }
  }

  private func writerMutex(action: () -> ())
  {
    dispatch_sync(writers) { action() }
  }

  /**
    Suspend either the readers or the writers queue, and
    resume the other queue in the process.

    By *definition*, this method is called while a mutex is locked.
  
    :param: queue either the readers or the writers queue.
  */

  private func suspend(queue: dispatch_queue_t)
  {
    if queue === readers
    {
      if readerState == .Running
      {
        dispatch_suspend(readers)
        readerState = .Suspended
        resume(writers)
      }
      return
    }

    if queue === writers
    {
      if writerState == .Running
      {
        dispatch_suspend(writers)
        writerState = .Suspended
        resume(readers)
      }
      return
    }

    assert(false, "Attempted to suspend an invalid queue")
  }

  /**
    Resume either the readers or the writers queue.

    By *definition*, this method is called while a mutex is locked.

    :param: queue either the readers or the writers queue.
  */

  private func resume(queue: dispatch_queue_t)
  {
    if queue === readers
    {
      if readerState == .Suspended
      {
        dispatch_resume(readers)
        readerState = .Running
      }
      return
    }

    if queue === writers
    {
      if writerState == .Suspended
      {
        dispatch_resume(writers)
        writerState = .Running
      }
      return
    }

    assert(false, "Attempted to resume an invalid queue")
  }

  // Logging

  private let logging = true
  private func log<PT>(object: PT) -> ()
  {
    if logging { syncprint(object) }
  }

  // Computed properties

  /**
    Report whether the channel capacity
  */

  override var capacity: Int { return channelCapacity }

  /**
    Determine whether the channel has been closed
  */

  override var isClosed: Bool { return closed }
  
  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It should perhaps be considered an error to close a channel that has
    already been closed, but in fact nothing will happen if it were to occur.
  */

  override func close()
  {
    if closed { return }

    channelMutex {
      self.doClose()
      self.resume(self.readers)
      self.resume(self.writers)
    }
  }

  /**
    Close the channel, specific implementation. This is used within close().
    By *definition*, this method is called while a mutex is locked.
  */

  private func doClose()
  {
    closed = true
  }

  /**
    Send an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func write(newElement: T)
  {
    if self.isClosed { return }

//    self.log("trying to send: \(newElement)")

    var hasSent = false
    while !hasSent
    {
      writerMutex { // A suspended writer queue will block here.
        self.channelMutex {
          if self.isFull && !self.isClosed
          {
            self.suspend(self.writers)
            return // to the top of the while loop and be suspended
          }

          // If Channel is closed, we could get here
          // while the queue is "full". Don't overflow.
          if !self.isFull { self.writeElement(newElement) }
          hasSent = true

//          self.log("sent element: \(newElement)")

          if self.isFull && !self.isClosed
          { // Preemptively suspend writers queue when channel is full
            self.suspend(self.writers)
          }
          else
          { // Channel is not empty; resume the readers queue.
            self.resume(self.readers)
          }
        }
      }
    }
  }

  /**
    Write an element to the channel buffer, specific implementation.
    This is used within write(newElement: T).
    By *definition*, this method is called while a mutex is locked.
  */
  private func writeElement(newElement: T)
  {
    _ = newElement
  }

  /**
    Receive the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func read() -> T?
  {
//    let id = readerCount++
//    self.log("trying to receive #\(id)")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      readerMutex { // A suspended reader queue will block here.
        self.channelMutex {
          if self.isEmpty && !self.isClosed
          {
            self.suspend(self.readers)
            return // to the top of the while loop and be suspended
          }

          oldElement = self.readElement()
          hasRead = true

//          self.log("reader \(id) received \(oldElement)")

          if self.isEmpty && !self.isClosed
          { // Preemptively suspend readers on empty channel
            self.suspend(self.readers)
          }
          else
          { // Channel is not full; resume the writers queue.
          self.resume(self.writers)
          }
        }
      }
    }

    assert(oldElement != nil || self.isClosed)

    return oldElement
  }

  /**
    Read an from the channel buffer, specific implementation.
    This is used within read() ->T?
    By *definition*, this method is called while a mutex is locked.
  */
  private func readElement() ->T?
  {
    return nil
  }

  override func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    async {
      var hasRead = false
      while !hasRead
      {
        self.readerMutex { // A suspended reader queue will block here.
          self.channelMutex {
            if self.isEmpty && !self.isClosed && !channel.isClosed
            {
              self.suspend(self.readers)
              return // to the top of the while loop and be suspended
            }

            channel.channelMutex {
              if !channel.isClosed
              {
                let selection = Selection(messageID: messageID, messageData: self.readElement())
                channel.selectSend(selection)
              }
            }
            hasRead = true

            if self.isEmpty && !self.isClosed
            { // Preemptively suspend readers on empty channel
              self.suspend(self.readers)
            }
            else
            { // Channel is not full; resume the writers queue.
              self.resume(self.writers)
            }
          }
        }
      }
    }
    
    return { self.channelMutex { self.resume(self.readers) } }
  }
}


/**
  A buffered channel with an N>1 element buffer
*/

class BufferedNChan<T>: BufferedChan<T>
{
  private var q: Queue<T>

  override init(var _ capacity: Int)
  {
    if capacity < 1 { capacity = 1 }

    self.q = Queue<T>()
    super.init(capacity)
  }

  override var isEmpty: Bool { return q.isEmpty }

  override var isFull: Bool { return q.count >= capacity }

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

class Buffered1Chan<T>: BufferedChan<T>
{
  private var element: T?

  override init(_ capacity: Int)
  {
    element = nil
    super.init(1)
  }

  convenience init()
  {
    self.init(1)
  }

  override var isEmpty: Bool { return (element == nil) }

  override var isFull: Bool  { return (element != nil) }

  private override func writeElement(newElement: T)
  {
    element = newElement
  }

  private override func readElement() ->T?
  {
    if let oldElement = self.element
    {
      self.element = nil
      return oldElement
    }
    return nil
  }
}

/**
  A one-element, buffered channel which will only ever transmit one message.
  The first successful write operation immediately closes the channel.
*/

public class SingletonChan<T>: Buffered1Chan<T>
{
  public init()
  {
    super.init(1)
  }

  override func writeElement(newElement: T)
  {
    super.writeElement(newElement)
    doClose()
  }
}

extension SelectChan: SelectionChannel
{
  /**
    selectMutex() must be used to send data to SelectChan in a thread-safe manner
  */

  public func selectMutex(action: () -> ())
  {
    if !self.isClosed
    {
      channelMutex { action() }
    }
  }

  /**
    selectSend(), used within the closure sent to selectMutex(), will send data to SelectionChannel
  */
  typealias WrittenElement=T

  public func selectSend(newElement: WrittenElement)
  {
    super.writeElement(newElement)
  }
}

/**
  A channel with no backing store.
  Send operations block until a receiver is ready.
  Conversely, receive operations block until a sender is ready.
*/

class UnbufferedChan<T>: BufferedChan<T>
{
  private var element: T? = nil
  private var blockedReaders: Int32
  private var blockedWriters: Int32

  init()
  {
    element = nil
    blockedReaders = 0
    blockedWriters = 0
    super.init(0)
  }

  override var isEmpty: Bool { return (element == nil) }
  override var isFull: Bool  { return (element != nil) }

  /**
    Tell whether the channel is ready to transfer data.

    An unbuffered channel should always look empty to an external observer.
    What is relevant internally is whether the data "is ready" to be transferred to a receiver.
  
    :return: whether the data is ready for a receive operation.
  */

  var isReady: Bool { return (element != nil) }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It should perhaps be considered an error to close a channel that has
    already been closed, but in fact nothing will happen if it were to occur.
  */

  override func close()
  {
    if closed { return }

//    self.log("closing 0-channel")
    super.close()
  }

  /**
    Write an element to the channel

    If no reader is ready to receive, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func write(newElement: T)
  {
    if self.isClosed { return }

//    self.log("writer \(newElement) is trying to send")

    var hasSent = false
    while !hasSent
    {
      // self.blockedWriters += 1 -- atomically
      OSAtomicIncrement32(&self.blockedWriters)

      writerMutex {        // A suspended writer queue will block here.
        self.channelMutex {
          self.blockedWriters -= 1

          self.suspend(self.writers) // will also resume readers

          if (self.blockedReaders < 1 || self.isReady) && !self.isClosed
          {
//            self.log("writer \(newElement) thinks there are \(self.blockedReaders) blocked readers")
            return // to the top of the loop and be suspended
          }

          assert(!self.isReady || self.isClosed, "Messed up an unbuffered send")

          self.writeElement(newElement)
          hasSent = true

          // Surely there is a reader waiting
          assert(self.blockedReaders > 0 || self.isClosed, "No receiver available!")

//          self.log("writer \(newElement) has successfully sent")
        }
      }
    }
  }

  private override func writeElement(newElement: T)
  {
    element = newElement
  }

  /**
    Read an element from the channel.

    If the channel is empty, this call will block until an element is available.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func read() -> T?
  {
//    let id = readerCount++
//    self.log("reader \(id) is trying to receive")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      // self.blockedReaders += 1 -- atomically
      OSAtomicIncrement32(&self.blockedReaders)

      readerMutex {        // A suspended reader queue will block here.
        self.channelMutex {
          self.blockedReaders -= 1

          if !self.isReady && !self.isClosed
          {
            self.suspend(self.readers) // will also resume writers
//            self.log("reader \(id) thinks there are \(self.blockedWriters) blocked writers")
            return // to the top of the loop and be suspended
          }

          assert(self.isReady || self.isClosed, "Messed up an unbuffered receive")

          oldElement = self.readElement()
          hasRead = true

          if self.blockedReaders > 0
          { // If other readers are waiting, wait for next writer.
            self.suspend(self.readers)
          }
          else if self.blockedWriters == 0 && self.blockedReaders == 0
          { // If both queues are empty, none should be suspended
            self.resume(self.writers)
          }
//          self.log("reader \(id) received \(oldElement)")
        }
      }
    }

    return oldElement
  }

  private override func readElement() ->T?
  {
    if let oldElement = self.element
    {
      self.element = nil
      return oldElement
    }
    return nil
  }

  override func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
  {
    async {
      var hasRead = false
      while !hasRead
      {
        // self.blockedReaders += 1 -- atomically
        OSAtomicIncrement32(&self.blockedReaders)

        self.readerMutex {        // A suspended reader queue will block the thread here.
          self.channelMutex {
            self.blockedReaders -= 1

            if !self.isReady && !self.isClosed
            {
              self.suspend(self.readers) // will also resume writers
              return // to the top of the loop and be suspended
            }

            assert(self.isReady || self.isClosed, "Messed up an unbuffered receive")

            channel.channelMutex {
              if !channel.isClosed
              {
                let selection = Selection(messageID: messageID, messageData: self.readElement())
                channel.selectSend(selection)
              }
            }
            hasRead = true

            if self.blockedReaders > 0
            { // If other readers are waiting, wait for next writer.
              self.suspend(self.readers)
            }
            else if self.blockedWriters == 0 && self.blockedReaders == 0
            { // If both queues are empty, none should be suspended
              self.resume(self.writers)
            }
          }
        }
      }
    }

    return {
      self.channelMutex { if self.blockedReaders > 0 { self.resume(self.readers) } }
    }
  }
}

// Used to elucidate/troubleshoot message arrival order
//private var readerCount = 0
