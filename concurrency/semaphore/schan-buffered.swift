//
//  schan-bufferedN.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  This solution adapted from:
  Oracle Multithreaded Programming Guide, Chapter 4, section 5: "Semaphores"
  http://docs.oracle.com/cd/E19455-01/806-5257/6je9h032s/index.html
*/

final class SBufferedChan<T>: Chan<T>
{
  private var buffer: UnsafeMutablePointer<T>

  // housekeeping variables

  private let capacity: Int
  private let mask: Int

  // housekeeping variables

  private var head = 0
  private var tail = 0

  private var headptr: UnsafeMutablePointer<T>
  private var tailptr: UnsafeMutablePointer<T>

  private let filled: dispatch_semaphore_t
  private let empty:  dispatch_semaphore_t

  private var mutex = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    filled = dispatch_semaphore_create(0)!
    empty =  dispatch_semaphore_create(capacity)!

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
    buffer = UnsafeMutablePointer.alloc(mask+1)
    headptr = buffer
    tailptr = buffer
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
      headptr = headptr.successor()
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
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }

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

    OSSpinLockLock(&mutex)
    closed = true
    OSSpinLockUnlock(&mutex)

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
    OSSpinLockLock(&mutex)

    if closed
    {
      OSSpinLockUnlock(&mutex)
      dispatch_semaphore_signal(empty)
      return false
    }

    tailptr.initialize(newElement)
    tail += 1
    switch tail&mask
    {
    case 0:  tailptr = buffer
    default: tailptr = tailptr.successor()
    }

    OSSpinLockUnlock(&mutex)
    dispatch_semaphore_signal(filled)

    return true
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

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)
    OSSpinLockLock(&mutex)

    if closed && head >= tail
    {
      OSSpinLockUnlock(&mutex)
      dispatch_semaphore_signal(filled)
      return nil
    }

    let element = headptr.move()
    head += 1
    switch head&mask
    {
    case 0:  headptr = buffer
    default: headptr = headptr.successor()
    }

    OSSpinLockUnlock(&mutex)
    dispatch_semaphore_signal(empty)

    return element
  }
}
