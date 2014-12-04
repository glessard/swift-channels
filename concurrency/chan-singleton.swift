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

public final class SingletonChan<T>: pthreadChan<T>
{
  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    let channel = SingletonChan()
    return (Sender.Wrap(channel), Receiver.Wrap(channel))
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

  // Initialization and destruction

  public override init()
  {
    element = nil
    super.init()
  }

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return elementsWritten <= elementsRead
  }

  final override var isFull: Bool
  {
    return elementsWritten > elementsRead
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
    let reader = OSAtomicIncrement64Barrier(&readerCount)

    if (elementsWritten < 0) && !self.closed
    {
      pthread_mutex_lock(channelMutex)
      // block until the channel is no longer empty
      while (elementsWritten < 0) && !self.closed
      {
        blockedReaders += 1
        pthread_cond_wait(readCondition, channelMutex)
        blockedReaders -= 1
      }
      pthread_mutex_unlock(channelMutex)
    }

    let element: T? = {
      if reader == 0
      {
        if let e = self.element
        {
          OSAtomicIncrement64Barrier(&self.elementsRead)
          self.element = nil
          return e
        }
      }
      return nil
    }()

    if blockedReaders > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }

    return element
  }
}
