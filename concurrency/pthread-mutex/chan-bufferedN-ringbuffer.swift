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
  private final var buffer: UnsafeMutablePointer<T>

  private final let capacity: Int
  private final let mask: Int

  // housekeeping variables

  private final var head = 0
  private final var tail = 0

  private final var headptr: UnsafeMutablePointer<T>
  private final var tailptr: UnsafeMutablePointer<T>

  // Initialization and destruction

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v |= v >> 32

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.alloc(mask+1)
    headptr = buffer
    tailptr = buffer

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
      if (i&mask == 0) { headptr = buffer }
      headptr.destroy()
      headptr.successor()
    }

    buffer.dealloc(mask+1)
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
    if self.closed { return false }

    pthread_mutex_lock(channelMutex)
    while (head+capacity <= tail) && !self.closed
    { // block while channel is full
      blockedWriters += 1
      pthread_cond_wait(writeCondition, channelMutex)
      blockedWriters -= 1
    }

    var success = false
    if !closed
    {
      tailptr.initialize(newElement)
      tailptr = tailptr.successor()
      tail += 1
      if (tail&mask == 0) { tailptr = buffer }
      success = true
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
    return success
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if self.closed && head >= tail { return nil }

    pthread_mutex_lock(channelMutex)

    while (head >= tail) && !self.closed
    { // block while channel is empty
      blockedReaders += 1
      pthread_cond_wait(readCondition, channelMutex)
      blockedReaders -= 1
    }

    if closed && tail <= head
    {
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
      return nil
    }

    let element = headptr.move()
    headptr = headptr.successor()
    head += 1
    if (head&mask == 0) { headptr = buffer }

    if self.closed && blockedReaders > 0
    { // No reason to block
      pthread_cond_signal(readCondition)
    }
    if blockedWriters > 0
    { // Channel isn't full
      pthread_cond_signal(writeCondition)
    }

    pthread_mutex_unlock(channelMutex)

    return element
  }
}
