//
//  schan-buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  This solution adapted from:
  Oracle Multithreaded Programming Guide, Chapter 4, section 5: "Semaphores"
  http://docs.oracle.com/cd/E19455-01/806-5257/6je9h032s/index.html
*/

final class SBufferedChan<T>: Chan<T>
{
  private let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  private let capacity: Int
  private let mask: Int

  private var head = 0
  private var tail = 0

  private let filled: dispatch_semaphore_t
  private let empty:  dispatch_semaphore_t

  private var wlock = OS_SPINLOCK_INIT
  private var rlock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : min(capacity, 32768)

    filled = dispatch_semaphore_create(0)!
    empty =  dispatch_semaphore_create(self.capacity)!

    // find the next power of 2 that is >= self.capacity
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
      dispatch_semaphore_signal(empty)
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

  final override func close()
  {
    if closed { return }

    OSSpinLockLock(&wlock)
    closed = true
    OSSpinLockUnlock(&wlock)

    dispatch_semaphore_signal(filled)
    dispatch_semaphore_signal(empty)
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  final override func put(newElement: T) -> Bool
  {
    if closed { return false }

    dispatch_semaphore_wait(empty, DISPATCH_TIME_FOREVER)
    OSSpinLockLock(&wlock)

    if !closed
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail = tail &+ 1

      OSSpinLockUnlock(&wlock)
      dispatch_semaphore_signal(filled)
      return true
    }
    else
    {
      OSSpinLockUnlock(&wlock)
      dispatch_semaphore_signal(empty)
      return false
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  final override func get() -> T?
  {
    if closed && (tail &- head) <= 0 { return nil }

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)
    OSSpinLockLock(&rlock)

    if (tail &- head) > 0
    {
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1

      OSSpinLockUnlock(&rlock)
      dispatch_semaphore_signal(empty)
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      OSSpinLockUnlock(&rlock)
      dispatch_semaphore_signal(filled)
      return nil
    }
  }
}
