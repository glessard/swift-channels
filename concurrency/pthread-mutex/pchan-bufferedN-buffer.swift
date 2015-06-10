//
//  chan-bufferedN-buffer.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses an "unsafe" buffer as a backing store.
*/

final class PBufferedBChan<T>: pthreadsChan<T>
{
  private final let buffer: UnsafeMutablePointer<T>

  private final let capacity: Int64
  private final let mask: Int64

  // housekeeping variables

  private final var head: Int64 = 0
  private final var tail: Int64 = 0

  // Initialization and destruction

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : Int64(capacity)

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v |= v >> 32

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.alloc(Int(mask+1))

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  deinit
  {
    for i in head..<tail
    {
      buffer.advancedBy(Int(i&mask)).destroy()
    }
    buffer.dealloc(Int(mask+1))
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

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    pthread_mutex_lock(&channelMutex)
    while (head+capacity <= tail) && !closed
    { // block while channel is full
      blockedWriters += 1
      pthread_cond_wait(&writeCondition, &channelMutex)
      blockedWriters -= 1
    }

    if !closed
    {
      buffer.advancedBy(Int(tail&mask)).initialize(newElement)
      tail += 1
    }
    let sent = !closed

    if blockedReaders > 0
    { // Channel is not empty
      pthread_cond_signal(&readCondition)
    }
    else if closed || head+capacity > tail && blockedWriters > 0
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
    if closed && head >= tail { return nil }

    pthread_mutex_lock(&channelMutex)

    while (head >= tail) && !closed
    { // block while channel is empty
      blockedReaders += 1
      pthread_cond_wait(&readCondition, &channelMutex)
      blockedReaders -= 1
    }

    if head < tail
    {
      let element = buffer.advancedBy(Int(head&mask)).move()
      head += 1

      if blockedWriters > 0
      { // Channel isn't full
        pthread_cond_signal(&writeCondition)
      }
      else if closed || head < tail && blockedReaders > 0
      { // No reason to block
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
