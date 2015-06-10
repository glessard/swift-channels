//
//  qchan-buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a queue of semaphores for scheduling.
*/

final class QBufferedChan<T>: Chan<T>
{
  private let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  private let capacity: Int
  private let mask: Int

  private var head = 0
  private var tail = 0

  private let readerQueue = FastQueue<ChannelSemaphore>()
  private let writerQueue = FastQueue<ChannelSemaphore>()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : min(capacity, 32768)

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.alloc(mask+1)

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  deinit
  {
    while tail &- head > 0
    {
      buffer.advancedBy(head&mask).destroy()
      head = head &+ 1
    }
    buffer.dealloc(mask+1)
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return (tail &- head) <= 0
  }

  final override var isFull: Bool
  {
    return (tail &- head) >= capacity
  }

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }

  // MARK: ChannelType methods

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

    OSSpinLockLock(&lock)
    closed = true

    // Unblock waiting threads.
    if let rs = readerQueue.dequeue()
    {
      rs.signal()
    }
    else if let ws = writerQueue.dequeue()
    {
      ws.signal()
    }
    OSSpinLockUnlock(&lock)
  }

  /**
    Stop the thread on a new semaphore obtained from the SemaphorePool

    The new semaphore is enqueued to readerQueue or writerQueue, and
    will be used as a signal to resume the thread at a later time.

    - parameter lock: a semaphore that is currently held by the calling thread.
    - parameter queue: the queue to which the signal should be appended
  */

  private func wait(queue: FastQueue<ChannelSemaphore>)
  {
    assert(lock != 0, "Lock must be locked upon entering \(__FUNCTION__)")

    let threadLock = SemaphorePool.Obtain()
    queue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    threadLock.wait()
    SemaphorePool.Return(threadLock)
    OSSpinLockLock(&lock)
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    - parameter element: the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    while !closed && (tail &- head) >= capacity
    {
      wait(writerQueue)
    }

    if !closed
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail = tail &+ 1
    }
    let sent = !closed

    if let rs = readerQueue.dequeue()
    {
      rs.signal()
    }
    else if (tail &- head) < capacity || closed, let ws = writerQueue.dequeue()
    {
      ws.signal()
    }

    OSSpinLockUnlock(&lock)
    return sent
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed && (tail &- head) <= 0 { return nil }

    OSSpinLockLock(&lock)

    while !closed && (tail &- head) <= 0
    {
      wait(readerQueue)
    }

    if (tail &- head) > 0
    {
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1

      if let ws = writerQueue.dequeue()
      {
        ws.signal()
      }
      else if (tail &- head) > 0 || closed, let rs = readerQueue.dequeue()
      {
        rs.signal()
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      if let ws = writerQueue.dequeue()
      {
        ws.signal()
      }
      else if let rs = readerQueue.dequeue()
      {
        rs.signal()
      }
      OSSpinLockUnlock(&lock)
      return nil
    }
  }
}
