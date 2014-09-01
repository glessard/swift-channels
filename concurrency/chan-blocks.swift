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

private enum QueueAction
{
  case Suspend
  case Resume
}

/**
A buffered channel.
*/

class BufferedChan<T>: Chan<T>
{
  private let channelCapacity: Int
  private var closed: Bool = false

  private let mutexq:  dispatch_queue_t
  private let readerq: dispatch_queue_t
  private let writerq: dispatch_queue_t

  private init(var _ capacity: Int)
  {
    channelCapacity = (capacity < 0) ? 0 : capacity

    mutexq =  dispatch_queue_create("channelmutex", DISPATCH_QUEUE_SERIAL)
    readerq = dispatch_queue_create("channelreadr", DISPATCH_QUEUE_SERIAL)
    writerq = dispatch_queue_create("channelwritr", DISPATCH_QUEUE_SERIAL)

    super.init()
  }

  // pseudo-keyword shortcuts for Grand Central Dispatch

  func channelMutex(action: () -> ())
  {
    dispatch_sync(mutexq)  { action() }
  }

  private func readerMutex(action: () -> ())
  {
    dispatch_sync(readerq) { action() }
  }

  private func writerMutex(action: () -> ())
  {
    dispatch_sync(writerq) { action() }
  }

  private var readerState: QueueState = .Running
  private var writerState: QueueState = .Running

  /**
    Set the state of the readers queue to .Running or .Suspended.
    By *definition*, this method is called while a mutex is locked.
  */

  private func readers(action: QueueAction)
  {
    switch action
    {
    case .Suspend:
      if readerState == .Running
      {
        dispatch_suspend(self.readerq)
        readerState = .Suspended
      }

    case .Resume:
      if readerState == .Suspended
      {
        dispatch_resume(self.readerq)
        readerState = .Running
      }
    }
  }

  /**
    Set the state of the writers queue to .Running or .Suspended.
    By *definition*, this method is called while a mutex is locked.
  */

  private func writers(action: QueueAction)
  {
    switch action
    {
    case .Suspend:
      if writerState == .Running
      {
        dispatch_suspend(self.writerq)
        writerState = .Suspended
      }

    case .Resume:
      if writerState == .Suspended
      {
        dispatch_resume(self.writerq)
        writerState = .Running
      }
    }
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
      self.readers(.Resume)
      self.writers(.Resume)
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

//    log("trying to send: \(newElement)")

    var hasSent = false
    while !hasSent
    {
      writerMutex { // A suspended writer queue will block here.
        self.channelMutex {
          if self.isFull && !self.isClosed
          {
            self.writers(.Suspend)
            return // to the top of the while loop and be suspended
          }

          // If Channel is closed, we could get here
          // while the queue is "full". Don't overflow.
          if !self.isFull { self.writeElement(newElement) }
          hasSent = true

          // Channel is not empty; resume the readers queue.
          self.readers(.Resume)

          // Preemptively suspend writers queue if appropriate
          if self.isFull && !self.isClosed { self.writers(.Suspend) }
        }
      }
    }

//    log("sent element: \(newElement)")
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
//    log("trying to receive #\(id)")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      readerMutex { // A suspended reader queue will block here.
        self.channelMutex {
          if self.isEmpty && !self.isClosed
          {
            self.readers(.Suspend)
            return // to the top of the while loop and be suspended
          }

          oldElement = self.readElement()
          hasRead = true

          // Preemptively suspend readers if appropriate
          if self.isEmpty && !self.isClosed { self.readers(.Suspend) }

          // Channel is not full; resume the writers queue.
          self.writers(.Resume)
        }
      }
    }

    assert(oldElement != nil || self.isClosed)

//    log("received #\(id)")

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

  override func selectRead(channel: SelectChan<Selectable>, message: Selectable) -> Signal
  {
    async {
      var hasRead = false
      while !hasRead
      {
        self.readerMutex { // A suspended reader queue will block here.
          self.channelMutex {
            if self.isEmpty && !self.isClosed && !channel.isClosed
            {
              self.readers(.Suspend)
              return // to the top of the while loop and be suspended
            }

            channel.channelMutex {
              if !channel.isClosed
              {
                channel.stash = SelectPayload(payload: self.readElement())
                channel.writeElement(message)
              }
            }
            hasRead = true

            // Preemptively suspend readers if appropriate
            if self.isEmpty && !self.isClosed { self.readers(.Suspend) }

            // Channel is not full, resume writers.
            self.writers(.Resume)
          }
        }
      }
    }
    
    return { self.channelMutex { self.readers(.Resume) } }
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
    let oldElement = self.element
    self.element = nil
    return oldElement
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


/**
  A channel with no backing store.
  Send operations block until a receiver is ready.
  Conversely, receive operations block until a sender is ready.
*/

class UnbufferedChan<T>: BufferedChan<T>
{
  private var element: T? = nil
  private var blockedReaders = 0
  private var blockedWriters = 0

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
  Close the channel

  Any items still in the channel remain and can be retrieved.
  New items cannot be added to a closed channel.

  It should perhaps be considered an error to close a channel that has
  already been closed, but in fact nothing will happen if it were to occur.
  */

  override func close()
  {
    if closed { return }

    log("closing 0-channel")
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

    log("writer \(newElement) is trying to send")

    var hasSent = false
    while !hasSent
    {
      channelMutex {
          self.blockedWriters += 1
      }
      // There is a race condition here when both queues just got suspended.
      writerMutex {
        self.channelMutex {
          self.blockedWriters -= 1

          self.log("writer \(newElement) thinks there are \(self.blockedReaders) blocked readers")
          if (self.blockedReaders < 1 || !self.isEmpty) && !self.isClosed
          {
            self.log("writer \(newElement) is suspending the writers queue")
            self.writers(.Suspend)
            self.readers(.Resume)
            return // to the top of the loop and be suspended
          }

          assert(self.isEmpty || self.isClosed, "Messed up an unbuffered send")

          self.writeElement(newElement)
          hasSent = true

          // Surely we can interest a reader
          assert(self.blockedReaders > 0 || self.isClosed, "No receiver available!")
          self.readers(.Resume)

          self.log("writer \(newElement) has successfully sent")
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
    let id = readerCount++
    log("reader \(id) is trying to receive")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      channelMutex {
          self.blockedReaders += 1
          if self.blockedWriters > 0
          { // Maybe we can interest a sender
            self.log("reader \(id) thinks there are \(self.blockedWriters) blocked writers")
            self.writers(.Resume)
          }
      }
      // There is a race condition here when both queues just got suspended.
      readerMutex {
        self.channelMutex {
          self.blockedReaders -= 1
          if self.isEmpty && !self.isClosed
          {
            self.log("reader \(id) is suspending the readers queue")
            self.readers(.Suspend)
            return // to the top of the loop and be suspended
          }

          assert(!self.isEmpty || self.isClosed, "Messed up an unbuffered receive")

          oldElement = self.readElement()
          hasRead = true

          self.writers(.Resume)

          self.log("reader \(id) received \(oldElement)")
        }
      }
    }

    return oldElement
  }

  private override func readElement() ->T?
  {
    let oldElement = self.element
    self.element = nil
    return oldElement
  }
}

var readerCount = 0
