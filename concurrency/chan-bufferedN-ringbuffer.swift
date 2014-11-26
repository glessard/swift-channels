//
//  chan-bufferedN-ringbuffer.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses an array as a backing store.
*/

final class BufferedAChan<T>: pthreadChan<T>
{
  private final let capacity: Int

  private final var buffer: Array<T?>
  private final let buflen: Int

  // housekeeping variables

  private final var head = 0
  private final var tail = 0

  // Initialization and destruction

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    buflen = capacity // restrict this to powers of two for potentially better speed.
    buffer = Array<T?>(count: buflen, repeatedValue: nil)

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  // Computed property accessors

  final override var isEmpty: Bool
  {
    return head >= tail
  }

  final override var isFull: Bool
  {
    return head+capacity <= tail
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
    while (head+capacity <= tail) && !self.closed
    { // block while channel is full
      blockedWriters += 1
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    if !self.closed
    {
      buffer[tail%buflen] = newElement
      tail += 1
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

  override func take() -> T?
  {
    pthread_mutex_lock(channelMutex)

    while (head >= tail) && !self.closed
    { // block while channel is empty
      blockedReaders += 1
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    if self.closed && (head >= tail)
    {
      buffer[head%buflen] = nil
    }
    else
    {
      assert(head < tail, "Inconsistent state in BufferedAChan<T>")
    }

    let oldElement = buffer[head%buflen]
    head += 1

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
