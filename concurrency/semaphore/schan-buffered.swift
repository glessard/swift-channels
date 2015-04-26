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

  private let capacity: Int64
  private let mask: Int64

  private var head: Int64 = 0
  private var tail: Int64 = 0

  private let filled: ChannelSemaphore
  private let empty:  ChannelSemaphore

  private var wlock = OS_SPINLOCK_INIT
  private var rlock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : Int64(capacity)

    filled = ChannelSemaphore(value: 0)
    empty =  ChannelSemaphore(value: Int32(self.capacity))

    // find the next power of 2 that is >= self.capacity
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    v |= v >> 32
    // the answer is v+1

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
    precondition(head <= tail, __FUNCTION__)
    for i in head..<tail
    {
      buffer.advancedBy(Int(i&mask)).destroy()
      empty.signal()
    }
    buffer.dealloc(Int(mask+1))
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return head >= tail
  }

  final override var isFull: Bool
  {
    return head+capacity <= tail
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

    filled.signal()
    empty.signal()
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

    empty.wait()
    OSSpinLockLock(&wlock)

    if !closed
    {
      buffer.advancedBy(Int(tail&mask)).initialize(newElement)
      tail += 1

      OSSpinLockUnlock(&wlock)
      filled.signal()
      return true
    }
    else
    {
      OSSpinLockUnlock(&wlock)
      empty.signal()
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
    if closed && head >= tail { return nil }

    filled.wait()
    OSSpinLockLock(&rlock)

    if head < tail
    {
      let element = buffer.advancedBy(Int(head&mask)).move()
      head += 1

      OSSpinLockUnlock(&rlock)
      empty.signal()
      return element
    }
    else
    {
      assert(closed, __FUNCTION__)
      OSSpinLockUnlock(&rlock)
      filled.signal()
      return nil
    }
  }
}
