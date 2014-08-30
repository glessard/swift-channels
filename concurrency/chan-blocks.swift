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
    if capacity < 1 { capacity = 1 }

    channelCapacity = capacity

    mutexq =  dispatch_queue_create("channelmutex", DISPATCH_QUEUE_SERIAL)
    readerq = dispatch_queue_create("channelreadr", DISPATCH_QUEUE_SERIAL)
    writerq = dispatch_queue_create("channelwritr", DISPATCH_QUEUE_SERIAL)

    super.init()
  }

  // pseudo-keyword shortcuts for Grand Central Dispatch

  private func channelMutex(action: () -> ())
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

  private func reader(action: QueueAction)
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

  private func writer(action: QueueAction)
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

  private let logging = false
  private func log(message: String) -> ()
  {
    if logging { syncprint(message) }
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
      self.log("closing buffered channel")
      self.reader(.Resume)
      self.writer(.Resume)
      self.doClose()
    }
  }

  private func doClose()
  {
    closed = true
  }

  /**
  Append an element to the channel

  If the channel is full, this call will block.
  If the channel has been closed, no action will be taken.

  :param: element the new element to be added to the channel.
  */

  override func write(newElement: T)
  {
    if self.closed { return }

    log("attempting to write to buffered channel")

    var blockWriter = !self.isClosed

    while (blockWriter == true)
    {
      // loop here while the channel is full
      writerMutex {
        self.channelMutex {
          self.writer(.Suspend)
          blockWriter = self.isFull && !self.closed
        }
      }
    }

    channelMutex {
      // If Channel is closed, we could get here while
      // the queue is "full". Don't overflow.
      if !self.isFull { self.writeElement(newElement) }

      // Channel is not empty; signal this.
      self.reader(.Resume)

      // Allow the next writer an attempt
      if !self.isFull { self.writer(.Resume) }

      assert(!self.isEmpty)
    }
    log("wrote to buffered channel")
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
  Return the oldest element from the channel.

  If the channel is empty, this call will block.
  If the channel is empty and closed, this will return nil.

  :return: the oldest element from the channel.
  */

  override func read() -> T?
  {
    log("attempting to read from buffered channel")

    var blockReader = !self.isClosed

    while (blockReader == true)
    {
      // loop here while the channel is empty
      readerMutex {
        self.channelMutex {
          self.reader(.Suspend)
          blockReader = self.isEmpty && !self.closed
        }
      }
    }

    var oldElement: T?
    channelMutex {
      oldElement = self.readElement()

      // Channel is not full; signal this.
      self.writer(.Resume)

      // Allow the next reader an attempt
      if !self.isEmpty { self.reader(.Resume) }
    }

    assert(oldElement != nil || self.isClosed)

    log("read from buffered channel")

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

//  override func selectRead(channel: SelectChan<Selectable>, message: Selectable) -> Signal
//  {
//    async {
//      pthread_mutex_lock(self.channelMutex)
//      while self.isEmpty && !self.isClosed && !channel.isClosed
//      {
//        pthread_cond_wait(self.readCondition, self.channelMutex)
//      }
//
//      channel.mutexAction {
//        if !channel.isClosed
//        {
//          channel.stash = SelectPayload(payload: self.readElement())
//          channel <- message
//        }
//      }
//
//      pthread_cond_signal(channel.readCondition)
//
//      pthread_cond_signal(self.writeCondition)
//      if self.closed { pthread_cond_signal(self.readCondition) }
//      pthread_mutex_unlock(self.channelMutex)
//    }
//    
//    return Signal { self.channelMutex { self.reader(.Resume) } }
//  }
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
A one-element channel which will only ever transmit one message.
The first successful write operation immediately closes the channel.
*/

public class SingletonChan<T>: Buffered1Chan<T>
{
  public init()
  {
    super.init(1)
  }

  private override func writeElement(newElement: T)
  {
    super.writeElement(newElement)
    doClose()
  }
}

