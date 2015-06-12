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

  private var closed = 0

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
      OSAtomicIncrementLongBarrier(&head)
      buffer.advancedBy(head&mask).destroy()
      dispatch_semaphore_signal(empty)
    }
    buffer.dealloc(mask+1)
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool { return (tail &- head) <= 0 }

  final override var isFull: Bool  { return (tail &- head) >= capacity }

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
      dispatch_semaphore_signal(filled)
      dispatch_semaphore_signal(empty)
    }
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    - parameter element: the new element to be added to the channel.
  */

  final override func put(newElement: T) -> Bool
  {
    if closed != 0 { return false }

    dispatch_semaphore_wait(empty, DISPATCH_TIME_FOREVER)

    if closed == 0
    {
      let newtail = OSAtomicIncrementLongBarrier(&tail)
      buffer.advancedBy(newtail&mask).initialize(newElement)

      dispatch_semaphore_signal(filled)
      return true
    }
    else
    {
      dispatch_semaphore_signal(empty)
      return false
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    - returns: the oldest element from the channel.
  */

  final override func get() -> T?
  {
    if closed != 0 && (tail &- head) <= 0 { return nil }

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)

    let newhead = OSAtomicIncrementLongBarrier(&head)
    if (tail &- newhead) >= 0
    {
      let element = buffer.advancedBy(newhead&mask).move()

      dispatch_semaphore_signal(empty)
      return element
    }
    else
    {
      precondition(closed != 0, __FUNCTION__)
      OSAtomicDecrementLongBarrier(&head)
      dispatch_semaphore_signal(filled)
      return nil
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
