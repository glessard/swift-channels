//
//  chan-pthreads.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  The basis for our real channels

  This solution adapted from:
  Oracle Multithreaded Programming Guide, "The Producer/Consumer Problem"
  http://docs.oracle.com/cd/E19455-01/806-5257/sync-31/index.html
*/

class pthreadChan<T>: Chan<T>
{
  // Instance variables

  final var closed = false
  final var blockedReaders = 0
  final var blockedWriters = 0

  // pthreads variables

  final var channelMutex:   UnsafeMutablePointer<pthread_mutex_t>
  final var readCondition:  UnsafeMutablePointer<pthread_cond_t>
  final var writeCondition: UnsafeMutablePointer<pthread_cond_t>

  // Initialization and destruction

  override init()
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
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  override func close()
  {
    if closed { return }

    closed = true

    // Unblock the threads waiting on our conditions.
    if blockedReaders > 0 || blockedWriters > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(writeCondition)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }
  }
}

/**
  A buffered channel.
*/

class BufferedChan<T>: pthreadChan<T>
{
  /**
    Append an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.isClosed { return }

    pthread_mutex_lock(channelMutex)

//    syncprint("writer \(newElement) is trying to send")

    while self.isFull && !self.isClosed
    { // wait while the channel is full
      blockedWriters += 1
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    // If Channel is closed, we could get here while
    // the queue is "full". Don't overflow.
    if !self.isFull { writeElement(newElement) }

//    syncprint("writer \(newElement) has successfully sent")

    // Channel is not empty; signal this.
    if blockedReaders > 0 { pthread_cond_signal(readCondition) }
    if self.isClosed && blockedWriters > 0 { pthread_cond_signal(writeCondition) }
    pthread_mutex_unlock(channelMutex)
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

  override func take() -> T?
  {
    pthread_mutex_lock(channelMutex)

//    let id = readerCount++
//    syncprint("reader \(id) is trying to receive")

    while self.isEmpty && !self.isClosed
    { // block while the channel is empty
      blockedReaders += 1
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    let oldElement = readElement()

    // Channel is not full; signal this.
    if blockedWriters > 0 { pthread_cond_signal(writeCondition) }
    if self.isClosed && blockedReaders > 0 { pthread_cond_signal(readCondition) }
    pthread_mutex_unlock(channelMutex)

//    syncprint("reader \(id) received \(oldElement)")

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
    Take the next element that can be read from self, and send it to the channel passed in as a parameter.

    :param: channel   the channel to which we're re-sending the element.
    :param: messageID an identifier to be sent as the return notification.

    :return: a closure that will unblock the thread if needed.
  */

//  override func selectReceive(channel: SelectChan<Selection>, messageID: Selectable) -> Signal
//  {
//    async {
//      pthread_mutex_lock(self.channelMutex)
//      while self.isEmpty && !self.isClosed && !channel.isClosed
//      {
//        self.blockedReaders += 1
//        pthread_cond_wait(self.readCondition, self.channelMutex)
//        self.blockedReaders -= 1
//      }
//
//      channel.selectMutex {
//        channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//      }
//
//      // Channel is not full; signal this.
//      if self.blockedWriters > 0 { pthread_cond_signal(self.writeCondition) }
//      if self.isClosed && self.blockedReaders > 0 { pthread_cond_signal(self.readCondition) }
//      pthread_mutex_unlock(self.channelMutex)
//    }
//
//    return {
//      if self.blockedReaders > 0
//      {
//        pthread_mutex_lock(self.channelMutex)
//        pthread_cond_signal(self.readCondition)
//        pthread_mutex_unlock(self.channelMutex)
//      }
//    }
//  }
}

/**
  A buffered channel with an N element circular buffer
*/

class pthreadsBufferedAChan<T>: BufferedChan<T>
{
  private var buffer: Array<T?>
  private let count: Int
  private var head = 0
  private var tail = 0

  init(_ capacity: Int)
  {
    count = (capacity < 1) ? 1 : capacity
    buffer = Array<T?>(count: count, repeatedValue: nil)
  }

  convenience override init()
  {
    self.init(1)
  }

//  override func capacityFunc() -> Int { return count }

//  override func isEmptyFunc() -> Bool { return head >= tail }
  final override var isEmpty: Bool  { return head >= tail }

//  override func isFullFunc() -> Bool { return head+count <= tail }
  final override var isFull: Bool { return head+count <= tail }

  private override func writeElement(newElement: T)
  {
    let index = tail%count
    buffer[index] = newElement
    tail += 1
  }

  private override func readElement() ->T?
  {
    let index = head%count
    let oldElement = buffer[index]
    buffer[index] = nil
    head += 1
    return oldElement
  }
}

/**
  The SelectionChannel methods for SelectChan
*/

//extension SelectChan //: SelectingChannel // (repeating this crashes swiftc)
//{
//  /**
//    selectMutex() must be used to send data to SelectChan in a thread-safe manner
//  
//    Actions which must be performed synchronously with the SelectChan should be passed to
//    selectMutex() as a closure. The closure will only be executed if the channel is still open.
//  */
//
//  public func selectMutex(action: () -> ())
//  {
//    if !self.isFull && !self.isClosed
//    {
//      pthread_mutex_lock(channelMutex)
//
//      action()
//
//      pthread_mutex_unlock(channelMutex)
//    }
//  }
//
//  /**
//    selectSend() will send data to a SelectChan.
//    It must be called within the closure sent to selectMutex() for thread safety.
//    By definition, this call occurs while this channel's mutex is locked for the current thread.
//  */
//
//  public func selectSend(newElement: T)
//  {
//    if !self.isFull && !self.isClosed
//    {
//      super.writeElement(newElement)
//      pthread_cond_signal(readCondition)
//    }
//  }
//}

/**
  A channel with no backing store.
  Send operations block until a receiver is ready.
  Conversely, receive operations block until a sender is ready.
*/

class UnbufferedChan<T>: pthreadChan<T>
{
  private var element: T?

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  override init()
  {
    element = nil
  }

  /**
    Write an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.closed { return }

    pthread_mutex_lock(channelMutex)

//    syncprint("writer \(newElement) is trying to send")

    while ( blockedReaders == 0 || elementsWritten > elementsRead ) && !self.closed
    { // wait while no reader is ready.
      blockedWriters += 1
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    assert(elementsWritten <= elementsRead || self.closed, "Messed up an unbuffered send")

    if !self.closed
    {
      self.element = newElement
      elementsWritten += 1
      //    syncprint("writer \(newElement) has successfully sent")
    }

    // Surely we can interest a reader
    assert(blockedReaders > 0 || self.isClosed, "No reader available!")
    pthread_cond_signal(readCondition)
    if self.closed && blockedWriters > 0 { pthread_cond_signal(writeCondition) }
    pthread_mutex_unlock(channelMutex)
  }

  /**
    Receive an element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func take() -> T?
  {
    pthread_mutex_lock(channelMutex)

//    let id = readerCount++
//    syncprint("reader \(id) is trying to receive")

    while elementsWritten <= elementsRead && !self.closed
    {
      if blockedWriters > 0
      { // Maybe we can interest a writer
        pthread_cond_signal(writeCondition)
      }
      // wait for a writer to signal us
      blockedReaders += 1
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    if self.closed && (elementsWritten <= elementsRead)
    {
      self.element = nil
    }
    else
    {
      assert(elementsRead < elementsWritten, "Inconsistent unbuffered channel state")
    }

    let oldElement = self.element
    elementsRead += 1

//    syncprint("reader \(id) received \(oldElement)")

    if blockedReaders > 0
    { // If other readers are waiting, signal a writer right away.
      if blockedWriters > 0 { pthread_cond_signal(writeCondition) }
      // If channel is closed, then signal a reader too.
      if self.isClosed { pthread_cond_signal(readCondition) }
    }
    pthread_mutex_unlock(channelMutex)

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

//  override func selectReceive(channel: SelectChan<Selection>, messageID: Selectable) -> Signal
//  {
//    async {
//      pthread_mutex_lock(self.channelMutex)
//
//      while !self.isReady && !self.isClosed
//      {
//        if self.blockedWriters > 0
//        {
//          // Maybe we can interest a writer
//          pthread_cond_signal(self.writeCondition)
//        }
//        // wait for a writer to signal us
//        self.blockedReaders += 1
//        pthread_cond_wait(self.readCondition, self.channelMutex)
//        self.blockedReaders -= 1
//      }
//
//      channel.selectMutex {
//        if !channel.isClosed
//        {
//          channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//        }
//      }
//
//      if self.blockedReaders > 0
//      { // If other readers are waiting, signal a writer right away.
//        if self.blockedWriters > 0 { pthread_cond_signal(self.writeCondition) }
//        // If channel is closed, then signal a reader too.
//        if self.isClosed { pthread_cond_signal(self.readCondition) }
//      }
//      pthread_mutex_unlock(self.channelMutex)
//    }
//
//    return {
//      if self.blockedReaders > 0
//      {
//        pthread_mutex_lock(self.channelMutex)
//        pthread_cond_broadcast(self.readCondition)
//        pthread_mutex_unlock(self.channelMutex)
//      }
//    }
//  }
}

// Used to elucidate/troubleshoot message arrival order
//private var readerCount = 0
