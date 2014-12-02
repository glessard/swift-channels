//
//  chan-buffered1.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a 1-element buffer.
*/

final class Buffered1Chan<T>: pthreadChan<T>
{
  private var element: T?

  // housekeeping variables

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Initialization and destruction

  override init()
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

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
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

    if self.closed && blockedWriters > 0
    { // No reason to block
      pthread_cond_signal(writeCondition)
    }
    if blockedReaders > 0
    { // Channel is not empty
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

  override func take() -> T?
  {
    pthread_mutex_lock(channelMutex)

    while (elementsWritten <= elementsRead) && !self.closed
    { // block while channel is empty
      blockedReaders += 1
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    if self.closed && (elementsWritten == elementsRead)
    {
      self.element = nil
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
    { // No reason to block
      pthread_cond_signal(readCondition)
    }
    if blockedWriters > 0
    { // Channel isn't full
      pthread_cond_signal(writeCondition)
    }
    pthread_mutex_unlock(channelMutex)

    return oldElement
  }
}
