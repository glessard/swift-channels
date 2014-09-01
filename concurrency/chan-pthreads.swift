//
//  chan-pthreads.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
The basis for our real channels
*/

class pthreadChan<T>: Chan<T>
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

    super.init()
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

  override var isClosed: Bool { return closed }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  override func close()
  {
    if closed { return }

    // Only bother with the mutex if necessary
    pthread_mutex_lock(channelMutex)

    doClose()

    // Unblock the threads waiting on our conditions.
    pthread_cond_signal(readCondition)
    pthread_cond_signal(writeCondition)
    pthread_mutex_unlock(channelMutex)
  }

  /**
      Close the channel, specific implementation. This is used within close().
      By *definition*, this method is called while a mutex is locked.
  */

  private func doClose()
  {
    self.closed = true
  }

  /**
    Write a new element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func write(newElement: T)
  {
    _ = newElement
  }

  /**
    Read the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func read() -> T?
  { // If we return 'nil', we should set the channel state to 'closed'
    close()
    return nil
  }
}

/**
  A buffered channel.
*/

class BufferedChan<T>: pthreadChan<T>
{
  private let channelCapacity: Int

  private init(var _ capacity: Int)
  {
    channelCapacity = (capacity < 1) ? 1 : capacity
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

  override var capacity: Int { return channelCapacity }

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

//    log("closing buffered channel")
    super.close()
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
      pthread_mutex_lock(self.channelMutex)
      while self.isEmpty && !self.isClosed && !channel.isClosed
      {
        pthread_cond_wait(self.readCondition, self.channelMutex)
      }

      channel.channelMutex {
        if !channel.isClosed
        {
          channel.stash = SelectPayload(payload: self.readElement())
          channel.writeElement(message)
        }
      }

      pthread_cond_signal(channel.readCondition)

      pthread_cond_signal(self.writeCondition)
      if self.closed { pthread_cond_signal(self.readCondition) }
      pthread_mutex_unlock(self.channelMutex)
    }

    return pthreadSignal(cond: readCondition, mutex: channelMutex)
  }
}

/**
  A buffered channel with an N>1 element buffer
*/

private class BufferedNChan<T>: BufferedChan<T>
{
  private var q: Queue<T>

  override init(var _ capacity: Int)
  {
    capacity = (capacity < 1) ? 1 : capacity

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

class Buffered1Chan<T>: BufferedChan<T>
{
  private var element: T? = nil

  private override init(var _ capacity: Int)
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
  The first successful write operation also closes the channel.
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

extension SelectChan
{
  func channelMutex(action: () -> ())
  {
    pthread_mutex_lock(channelMutex)

    action()

    // Unlock the readers and writers, just in case.
    // This is not particularly reasonable.
    pthread_cond_signal(readCondition)
    pthread_cond_signal(writeCondition)

    pthread_mutex_unlock(channelMutex)
  }
}

/**
  A channel with no backing store. Write operations block until a receiver is ready, while
  conversely read operations block until a sender is ready.
*/

class UnbufferedChan<T>: pthreadChan<T>
{
  private var element: T? = nil
  private var blockedReaders = 0
  private var blockedWriters = 0

  override init()
  {
    element = nil
    blockedReaders = 0
    blockedWriters = 0
    super.init()
  }

  override var isEmpty: Bool { return (element == nil) }

  override var isFull: Bool  { return (element != nil) }

  override var capacity: Int { return 0 }

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

  override func close()
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

  override func write(newElement: T)
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

  override func read() -> T?
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
