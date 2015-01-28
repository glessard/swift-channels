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

  // housekeeping variables

  private let capacity: Int
  private let mask: Int

  // housekeeping variables

  private var head = 0
  private var tail = 0

  private let filled: dispatch_semaphore_t
  private let empty:  dispatch_semaphore_t

  private var lock = OS_SPINLOCK_INIT

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
  }

  convenience override init()
  {
    self.init(1)
  }

  deinit
  {
    if head < tail
    {
      for i in head..<tail
      {
        buffer.advancedBy(i&mask).destroy()
      }
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
    return head+capacity >= tail
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

    OSSpinLockLock(&lock)
    closed = true
    OSSpinLockUnlock(&lock)

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
    OSSpinLockLock(&lock)

    if closed
    {
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_signal(empty)
      return false
    }

    buffer.advancedBy(tail&mask).initialize(newElement)
    tail += 1

    OSSpinLockUnlock(&lock)
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
    OSSpinLockLock(&lock)

    if closed && head >= tail
    {
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_signal(filled)
      return nil
    }

    let element = buffer.advancedBy(head&mask).move()
    head += 1

    OSSpinLockUnlock(&lock)
    dispatch_semaphore_signal(empty)

    return element
  }

  override func selectGet(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal
  {
    var j = OS_SPINLOCK_INIT
    var k = OS_SPINLOCK_INIT
    let g = dispatch_group_create()!

    async {
      OSSpinLockLock(&j)
      dispatch_semaphore_wait(self.filled, DISPATCH_TIME_FOREVER)
      OSSpinLockLock(&k)
      if dispatch_get_context(g) == abortSelect
      {
//        syncprint("abort select")
        return
      }
      OSSpinLockUnlock(&k)
      OSSpinLockUnlock(&j)

      OSSpinLockLock(&self.lock)

      if let s = semaphore.get()
      {
        var element: T? = nil
        if self.head < self.tail
        {
          element = self.buffer.advancedBy(self.head&self.mask).move()
          self.head += 1
        }

        if self.closed
        {
          OSSpinLockUnlock(&self.lock)
          dispatch_semaphore_signal(self.filled)
        }
        else
        {
          OSSpinLockUnlock(&self.lock)
          dispatch_semaphore_signal(self.empty)
        }

        let selection = Selection(selectionID: selectionID, selectionData: element)
        let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
        dispatch_set_context(s, context)
        dispatch_semaphore_signal(s)
      }
      else
      {
        OSSpinLockUnlock(&self.lock)
        dispatch_semaphore_signal(self.filled)
//        syncprint("not selected")
      }
    }

    return {
      if !OSSpinLockTry(&j)
      {
        if OSSpinLockTry(&k)
        {
          dispatch_set_context(g, abortSelect)
          dispatch_semaphore_signal(self.filled)
  //        syncprint("aborting")
          OSSpinLockUnlock(&k)
        }
      }
      OSSpinLockUnlock(&j)
    }
  }
}
