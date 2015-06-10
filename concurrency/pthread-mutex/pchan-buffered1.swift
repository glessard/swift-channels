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

final class PBuffered1Chan<T>: pthreadsChan<T>
{
  private let e = UnsafeMutablePointer<T>.alloc(1)

  // housekeeping variables

  private let capacity = 1
  private var elements = 0

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  deinit
  {
    if elements > 0
    {
      e.destroy()
    }
    e.dealloc(1)
  }

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return elements <= 0
  }

  final override var isFull: Bool
  {
    return elements >= capacity
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    pthread_mutex_lock(&channelMutex)
    while (elements >= capacity) && !closed
    { // block while channel is full
      blockedWriters += 1
      pthread_cond_wait(&writeCondition, &channelMutex)
      blockedWriters -= 1
    }

    if closed
    {
      pthread_cond_signal(&writeCondition)
      pthread_cond_signal(&readCondition)
      pthread_mutex_unlock(&channelMutex)
      return false
    }

    if !closed
    {
      e.initialize(newElement)
      elements += 1
    }
    let sent = !closed

    if blockedReaders > 0
    { // Channel is not empty
      pthread_cond_signal(&readCondition)
    }
    else if closed && blockedWriters > 0
    {
      pthread_cond_signal(&writeCondition)
    }

    pthread_mutex_unlock(&channelMutex)
    return sent
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    - returns: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed && elements <= 0 { return nil }

    pthread_mutex_lock(&channelMutex)

    while (elements <= 0) && !closed
    { // block while channel is empty
      blockedReaders += 1
      pthread_cond_wait(&readCondition, &channelMutex)
      blockedReaders -= 1
    }

    if elements > 0
    {
      let element = e.move()
      elements -= 1

      if blockedWriters > 0
      {
        pthread_cond_signal(&writeCondition)
      }
      else if closed && blockedReaders > 0
      {
        pthread_cond_signal(&readCondition)
      }
      pthread_mutex_unlock(&channelMutex)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      if blockedWriters > 0
      {
        pthread_cond_signal(&writeCondition)
      }
      else if blockedReaders > 0
      {
        pthread_cond_signal(&readCondition)
      }
      pthread_mutex_unlock(&channelMutex)
      return nil
    }
  }
}
