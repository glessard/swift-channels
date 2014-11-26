//
//  chan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A one-element channel which will only ever transmit one message:
  the first successful write operation closes the channel.
*/

public final class SingletonChan<T>: Chan<T>
{
  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    let channel = SingletonChan()
    return (ChanSender(channel), ChanReceiver(channel))
  }

  public class func Make(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make()
  }

  private var element: T?

  // housekeeping variables

  private var writerCount: Int64 = -1
  private var readerCount: Int64 = -1

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  private var closed = false
  private var blockedReaders = 0

  // pthreads variables

  private var channelMutex:   UnsafeMutablePointer<pthread_mutex_t>
  private var readCondition:  UnsafeMutablePointer<pthread_cond_t>

  // Initialization and destruction

  public override init()
  {
    element = nil

    channelMutex = UnsafeMutablePointer<pthread_mutex_t>.alloc(1)
    pthread_mutex_init(channelMutex, nil)

    readCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(readCondition, nil)
  }

  deinit
  {
    pthread_mutex_destroy(channelMutex)
    channelMutex.dealloc(1)

    pthread_cond_destroy(readCondition)
    readCondition.dealloc(1)
  }

  // Computed property accessors

  final override var isEmpty: Bool // isEmptyFunc() -> Bool
  {
    return elementsWritten <= elementsRead
  }

  final override var isFull: Bool // isFullFunc() -> Bool
  {
    return elementsWritten > elementsRead
  }

  final override var isClosed: Bool
  {
    return closed
  }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. This implementation doesn't do anything.
  */

  override func close()
  {
    if closed { return }

    closed = true

    // Unblock any thread waiting on our conditions.
    if blockedReaders > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }
  }
  
  /**
    Append an element to the channel

    This method will not block because only one send operation
    can occur in the lifetime of a SingletonChan.

    The first successful send will close the channel; further
    send operations will have no effect.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    let writer = OSAtomicIncrement64Barrier(&writerCount)

    if writer != 0
    { // if writer is not 0, this call is happening too late.
      return
    }

    element = newElement
    OSAtomicIncrement64Barrier(&elementsWritten)
    close()

    // Channel is not empty; unblock any waiting thread.
    if blockedReaders > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func take() -> T?
  {
    if (elementsWritten < 0) && !self.isClosed
    {
      pthread_mutex_lock(channelMutex)
      // block until the channel is no longer empty
      while (elementsWritten < 0) && !self.isClosed
      {
        blockedReaders += 1
        pthread_cond_wait(readCondition, channelMutex)
        blockedReaders -= 1
      }
      pthread_mutex_unlock(channelMutex)
    }

    let reader = OSAtomicIncrement64Barrier(&readerCount)
    let oldElement: T? = readElement(reader)

    if blockedReaders > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }

    return oldElement
  }

  private final func readElement(reader: Int64) -> T?
  {
    if reader == 0
    {
      let oldElement = self.element
      OSAtomicIncrement64Barrier(&elementsRead)
      // Whether to set self.element to nil is an interesting question.
      // If T is a reference type (or otherwise contains a reference), then
      // nulling is desirable to in order to avoid unnecessarily extending the
      // lifetime of the referred-to element.
      // In the case of SingletonChan, there is no contention at this point
      // when writing to self.element, nor is there the possibility of a 
      // flurry of messages. In other implementations, this will be different.
      self.element = nil
      return oldElement
    }
    return nil
  }
}
