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
    while tail &- head > 0
    {
      OSAtomicIncrementLongBarrier(&head)
      buffer.advancedBy(head&mask).destroy()
      empty.signal()
    }
    buffer.dealloc(mask+1)
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
      return Int(tail &- head) >= capacity
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

    if closed == 0
    {
      let index = OSAtomicIncrementLongBarrier(&tail)
      buffer.advancedBy(index&mask).initialize(newElement)

      filled.signal()
      return true
    }
    else
    {
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

    let index = OSAtomicIncrementLongBarrier(&head)
    if (tail &- index) >= 0
    {
      let element = buffer.advancedBy(index&mask).move()

      empty.signal()
      return element
    }
    else
    {
      assert(closed != 0, __FUNCTION__)
      OSAtomicDecrementLongBarrier(&head)
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
    let index = OSAtomicIncrementLongBarrier(&tail)
    if closed == 0 && index &- head <= capacity
    {
      buffer.advancedBy(index&mask).initialize(newElement)

      filled.signal()
      return true
    }
    else
    {
      OSAtomicDecrementLongBarrier(&tail)
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
    let index = OSAtomicIncrementLongBarrier(&head)
    if (tail &- index) >= 0
    {
      let element = buffer.advancedBy(index&mask).move()

      empty.signal()
      return element
    }
    else
    {
      assert(closed != 0, __FUNCTION__)
      OSAtomicDecrementLongBarrier(&head)
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

@inline(__always) private func OSAtomicIncrementLongBarrier(pointer: UnsafeMutablePointer<Int>) -> Int
{
  #if arch(x86_64) || arch(arm64) // 64-bit architecture
    return Int(OSAtomicIncrement64Barrier(UnsafeMutablePointer<Int64>(pointer)))
  #else // 32-bit architecture
    return Int(OSAtomicIncrement32Barrier(UnsafeMutablePointer<Int32>(pointer)))
  #endif
}

@inline(__always) private func OSAtomicDecrementLongBarrier(pointer: UnsafeMutablePointer<Int>) -> Int
{
  #if arch(x86_64) || arch(arm64) // 64-bit architecture
    return Int(OSAtomicDecrement64Barrier(UnsafeMutablePointer<Int64>(pointer)))
  #else // 32-bit architecture
    return Int(OSAtomicDecrement32Barrier(UnsafeMutablePointer<Int32>(pointer)))
  #endif
}
