//
//  chan-1buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a 1-element buffer.
*/

final class Buffered1Chan<T>: Chan<T>
{
  private var element: T?

  // housekeeping variables

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  private var closed = false
  private var blockedReaders = 0
  private var blockedWriters = 0

  // pthreads variables

  private var channelMutex:   UnsafeMutablePointer<pthread_mutex_t>
  private var readCondition:  UnsafeMutablePointer<pthread_cond_t>
  private var writeCondition: UnsafeMutablePointer<pthread_cond_t>

  // Initialization and destruction

  override init()
  {
    element = nil

    channelMutex = UnsafeMutablePointer<pthread_mutex_t>.alloc(1)
    pthread_mutex_init(channelMutex, nil)

    writeCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(writeCondition, nil)

    readCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(readCondition, nil)
  }

  deinit
  {
    pthread_mutex_destroy(channelMutex)
    channelMutex.dealloc(1)

    pthread_cond_destroy(writeCondition)
    writeCondition.dealloc(1)

    pthread_cond_destroy(readCondition)
    readCondition.dealloc(1)
  }

  // Computed property accessors

  override func isEmptyFunc() -> Bool
  {
    return elementsWritten <= elementsRead
  }

  override func isFullFunc() -> Bool
  {
    return elementsWritten > elementsRead
  }

  override func capacityFunc() -> Int
  {
    return 1
  }

  override func isClosedFunc() -> Bool
  {
    return closed
  }

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
  
  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func write(newElement: T)
  {
    if self.closed { return }

    pthread_mutex_lock(channelMutex)
    while (elementsWritten > elementsRead) && !self.closed
    { // block while channel is full
      blockedWriters += 1
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    if !self.closed
    {
      self.element = newElement
      elementsWritten += 1
    }

    // Channel is not empty; signal if appropriate
    if self.closed && blockedWriters > 0
    {
      pthread_cond_signal(writeCondition)
    }
    if blockedReaders > 0
    {
      pthread_cond_signal(readCondition)
    }

    pthread_mutex_unlock(channelMutex)
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

    while (elementsWritten <= elementsRead) && !self.closed
    { // block while channel is empty
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
      assert(elementsRead < elementsWritten, "Inconsistent 1-channel state")
    }

    let oldElement = self.element
    elementsRead += 1

    // Whether to set self.element to nil is an interesting question.
    // If T is a reference type (or otherwise contains a reference), then
    // nulling is desirable to in order to avoid unnecessarily extending the
    // lifetime of the referred-to element.
    // In the case of a potentially long-lived buffered channel, there is a
    // potential for contention at this point. This implementation is
    // choosing to take the risk of extending the life of its messages.
    // Also, setting self.element to nil at this point would be slow. Somehow.

    if self.closed && blockedReaders > 0
    {
      pthread_cond_signal(readCondition)
    }
    if blockedWriters > 0
    {
      pthread_cond_signal(writeCondition)
    }

    pthread_mutex_unlock(channelMutex)
    return oldElement
  }
}
