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

  private var filled: SChanSemaphore
  private var empty:  SChanSemaphore

  private var wlock = OS_SPINLOCK_INIT
  private var rlock = OS_SPINLOCK_INIT

  private var closed = 0

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : min(capacity, 32768)

    filled = SChanSemaphore(value: 0)
    empty =  SChanSemaphore(value: self.capacity)

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
    while (tail &- head) > 0
    {
      buffer.advancedBy(head&mask).destroy()
      head = head &+ 1
      empty.signal()
    }
    buffer.dealloc(Int(mask+1))
    empty.destroy()
    filled.destroy()
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

  final override var isClosed: Bool { return closed != 0 }

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
    if OSAtomicCompareAndSwapLongBarrier(0, 1, &closed)
    {
      filled.signal()
      empty.signal()
    }
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  final override func put(newElement: T) -> Bool
  {
    if closed != 0 { return false }

    empty.wait()
    OSSpinLockLock(&wlock)

    if closed == 0
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail = tail &+ 1

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
    if closed != 0 && (tail &- head) <= 0 { return nil }

    filled.wait()
    OSSpinLockLock(&rlock)

    if (tail &- head) > 0
    {
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1

      OSSpinLockUnlock(&rlock)
      empty.signal()
      return element
    }
    else
    {
      assert(closed != 0, __FUNCTION__)
      OSSpinLockUnlock(&rlock)
      filled.signal()
      return nil
    }
  }

  // MARK: SelectableChannelType methods

  override func selectPutNow(selection: Selection) -> Selection?
  {
    if empty.wait(DISPATCH_TIME_NOW)
    {
      return selection
    }
    else
    {
      return nil
    }
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    // the `empty` semaphore has already been decremented for this operation.
    OSSpinLockLock(&wlock)
    if closed == 0 && (tail &- head) < capacity
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail = tail &+ 1

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

  override func selectPut(select: ChannelSemaphore, selection: Selection)
  {
    if empty.wait(DISPATCH_TIME_NOW)
    {
      if select.setState(.Select)
      {
        select.selection = selection
        select.signal()
      }
      else
      { // let another reader through
        empty.signal()
      }
      return
    }

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      self.empty.wait()

      if select.setState(.Select)
      {
        select.selection = selection
        select.signal()
      }
      else
      { // let another writer through
        self.empty.signal()
      }
    }
  }

  override func selectGetNow(selection: Selection) -> Selection?
  {
    if filled.wait(DISPATCH_TIME_NOW)
    {
      return selection
    }
    else
    {
      return nil
    }
  }

  override func extract(selection: Selection) -> T?
  {
    // the `filled` semaphore has already been decremented for this operation.
    OSSpinLockLock(&rlock)
    if (tail &- head) > 0
    {
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1
      OSSpinLockUnlock(&rlock)
      empty.signal()
      return element
    }
    else
    {
      assert(closed != 0, __FUNCTION__)
      OSSpinLockUnlock(&rlock)
      filled.signal()
      return nil
    }
  }

  override func selectGet(select: ChannelSemaphore, selection: Selection)
  {
    if filled.wait(DISPATCH_TIME_NOW)
    {
      if select.setState(.Select)
      {
        select.selection = selection
        select.signal()
      }
      else
      { // let another reader through
        filled.signal()
      }
      return
    }

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      self.filled.wait()

      if select.setState(.Select)
      {
        select.selection = selection
        select.signal()
      }
      else
      { // let another reader through
        self.filled.signal()
      }
    }
  }
}
