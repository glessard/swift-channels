//
//  chan-blocks.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Housekeeping help for dispatch_queue_t objects.
  For some reason they don't expose their state at all,
  so we have to do this ourselves.
*/

private enum QueueState
{
  case Suspended
  case Running
}

/**
  Our basis for channel implementations based on Grand Central Dispatch

  This is an adaptation of a standard pthreads solution for the producer/consumer problem
  to the blocks-and-queues Weltanschauung of Grand Central Dispatch. It might not be optimal.
*/

class gcdChan<T>: Chan<T>
{
  // instance variables

  private var closed: Bool = false

  private let mutex:   dispatch_queue_t
  private let readers: dispatch_queue_t
  private let writers: dispatch_queue_t

  private var readerState: QueueState = .Running
  private var writerState: QueueState = .Running

  // Initialization

  private override init()
  {
    mutex   = dispatch_queue_create("channelmutex", DISPATCH_QUEUE_SERIAL)
    readers = dispatch_queue_create("channelreadq", DISPATCH_QUEUE_SERIAL)
    writers = dispatch_queue_create("channelwritq", DISPATCH_QUEUE_SERIAL)
  }

  // pseudo-keyword shortcuts for Grand Central Dispatch

  final private func channelMutex(action: () -> ())
  {
    dispatch_sync(mutex)   { action() }
  }

  final private func readerMutex(action: () -> ())
  {
    dispatch_sync(readers) { action() }
  }

  final private func writerMutex(action: () -> ())
  {
    dispatch_sync(writers) { action() }
  }

  /**
    Suspend either the readers or the writers queue, and
    resume the other queue in the process.

    By *definition*, this method is called while a mutex is locked.
  
    :param: queue either the readers or the writers queue.
  */

  final private func suspend(queue: dispatch_queue_t)
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

  final private func resume(queue: dispatch_queue_t)
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
    Determine whether the channel has been closed
  */

  override func isClosedFunc() -> Bool { return closed }
  
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
}

/**
  A buffered channel.
*/

class BufferedChan<T>: gcdChan<T>
{
  /**
    Append an element to the channel

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
    This is used within send(newElement: T).
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
    This is used within receive() ->T?
    By *definition*, this method is called while a mutex is locked.
  */
  private func readElement() ->T?
  {
    return nil
  }

  /**
    Take the next element that can be received from self,
    and send it to the channel passed in as a parameter.

    :param: channel   the channel to which we're re-sending the element.
    :param: messageID an identifier to be sent as the return notification.

    :return: a closure that will unblock the thread if needed.
  */

//  override func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
//  {
//    async {
//      var hasRead = false
//      while !hasRead
//      {
//        self.readerMutex { // A suspended reader queue will block here.
//          self.channelMutex {
//            if self.isEmpty && !self.isClosed && !channel.isClosed
//            {
//              self.suspend(self.readers)
//              return // to the top of the while loop and be suspended
//            }
//
//            channel.selectMutex {
//              channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//            }
//            hasRead = true
//
//            if self.isEmpty && !self.isClosed
//            { // Preemptively suspend readers when channel is empty
//              self.suspend(self.readers)
//            }
//            else
//            { // Channel is not full; resume the writers queue.
//              self.resume(self.writers)
//            }
//          }
//        }
//      }
//    }
//    
//    return { self.channelMutex { self.resume(self.readers) } }
//  }
}


/**
  A buffered channel with an N>1 element queue
*/

class BufferedQChan<T>: BufferedChan<T>
{
  private let count: Int
  private var q: Queue<T>

  init(var _ capacity: Int)
  {
    count = (capacity < 1) ? 1: capacity
    self.q = Queue<T>()
  }

  convenience override init()
  {
    self.init(1)
  }

  override func capacityFunc() -> Int { return count }

  override func isEmptyFunc() -> Bool { return q.isEmpty }

  override func isFullFunc() ->  Bool { return q.count >= count }

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

  override init()
  {
    element = nil
  }

  override func capacityFunc() -> Int { return 1 }

  override func isEmptyFunc() -> Bool { return (element == nil) }

  override func isFullFunc() ->  Bool  { return (element != nil) }

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
  public override init()
  {
    super.init()
  }

  private override func writeElement(newElement: T)
  {
    super.writeElement(newElement)
    doClose()
  }
}

/**
  The SelectionChannel methods for SelectChan
*/

//extension SelectChan //: SelectingChannel
//{
//  /**
//    selectMutex() must be used to send data to a SelectingChannel in a thread-safe manner
//
//    Actions which must be performed synchronously with the SelectChan should be passed to
//    selectMutex() as a closure. The closure will only be executed if the channel is still open.
//  */
//
//  public func selectMutex(action: () -> ())
//  {
//    if !self.isClosed
//    {
//      channelMutex { action() }
//    }
//  }
//
//  /**
//    selectSend() will send data to a SelectingChannel.
//    It must be called within the closure sent to selectMutex() for thread safety.
//    By definition, this call occurs while this channel's mutex is locked for the current thread.
//  */
//
//  public func selectSend(newElement: T)
//  {
//    super.writeElement(newElement)
//    self.resume(self.readers)
//  }
//}

/**
  A channel with no backing store.
  Send operations block until a receiver is ready.
  Conversely, receive operations block until a sender is ready.
*/

class UnbufferedChan<T>: gcdChan<T>
{
  private var element: T?
  private var blockedReaders: Int32 = 0
  private var blockedWriters: Int32 = 0

  override init()
  {
    element = nil
  }

  override func capacityFunc() -> Int  { return 0 }

  /**
  isEmpty is meaningless when capacity equals zero.
  However, receive() is nearly guaranteed to block, so return true.

  :return: true
  */

  override func isEmptyFunc() -> Bool { return true }

  /**
  isFull is meaningless when capacity equals zero.
  However, send() is nearly guaranteed to block, so return true.

  :return: true
  */

  override func isFullFunc() -> Bool  { return true }

  /**
    Tell whether the channel is ready to transfer data.

    An unbuffered channel should always look empty to an external observer.
    What is relevant internally is whether the data "is ready" to be transferred to a receiver.
  
    :return: whether the data is ready for a receive operation.
  */

  final var isReady: Bool { return (element != nil) }

  /**
    Close the channel
  */

  private override func doClose()
  {
//    self.log("closing 0-channel")
    super.doClose()
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
      OSAtomicIncrement32Barrier(&self.blockedWriters)

      writerMutex {        // A suspended writer queue will block here.
        self.channelMutex {
          OSAtomicDecrement32Barrier(&self.blockedWriters)

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

          if self.isClosed { self.resume(self.writers) }

//          self.log("writer \(newElement) has successfully sent")
        }
      }
    }
  }

  /**
    Write an element to the channel buffer, specific implementation.
    This is used within send(newElement: T).
    By *definition*, this method is called while a mutex is locked.
  */

  private func writeElement(newElement: T)
  {
    element = newElement
  }

  /**
    Receive an element from the channel.

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
      OSAtomicIncrement32Barrier(&self.blockedReaders)

      readerMutex {        // A suspended reader queue will block here.
        self.channelMutex {
          OSAtomicDecrement32Barrier(&self.blockedReaders)

          if !self.isReady && !self.isClosed
          {
            self.suspend(self.readers) // will also resume writers
//            self.log("reader \(id) thinks there are \(self.blockedWriters) blocked writers")
            return // to the top of the loop and be suspended
          }

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

  /**
    Read an from the channel buffer, specific implementation.
    This is used within receive() ->T?
    By *definition*, this method is called while a mutex is locked.
  */

  private func readElement() ->T?
  {
    if let oldElement = self.element
    {
      self.element = nil
      return oldElement
    }
    return nil
  }

  /**
    Take the next element that can be received from self, and send it to the channel passed in as a parameter.

    :param: channel   the channel to which we're re-sending the element.
    :param: messageID an identifier to be sent as the return notification.

    :return: a closure that will unblock the thread if needed.
  */

//  override func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
//  {
//    async {
//      var hasRead = false
//      while !hasRead
//      {
//        // self.blockedReaders += 1 -- atomically
//        OSAtomicIncrement32Barrier(&self.blockedReaders)
//
//        self.readerMutex {        // A suspended reader queue will block the thread here.
//          self.channelMutex {
//            OSAtomicDecrement32Barrier(&self.blockedReaders)
//
//            if !self.isReady && !self.isClosed
//            {
//              self.suspend(self.readers) // will also resume writers
//              return // to the top of the loop and be suspended
//            }
//
//            channel.selectMutex {
//              channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//            }
//            hasRead = true
//
//            if self.blockedReaders > 0
//            { // If other readers are waiting, wait for next writer.
//              self.suspend(self.readers)
//            }
//            else if self.blockedWriters == 0 && self.blockedReaders == 0
//            { // If both queues are empty, none should be suspended
//              self.resume(self.writers)
//            }
//          }
//        }
//      }
//    }
//
//    return {
//      self.channelMutex { if self.blockedReaders > 0 { self.resume(self.readers) } }
//    }
//  }
}

// Used to elucidate/troubleshoot message arrival order
//private var readerCount = 0
