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
  fileprivate let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  fileprivate let capacity: Int
  fileprivate let mask: Int

  fileprivate var head = 0
  fileprivate var tail = 0

  fileprivate let filled: SChanSemaphore
  fileprivate let empty:  SChanSemaphore

  fileprivate var closed = 0

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : min(capacity, 32768)

    filled = SChanSemaphore()
    empty =  SChanSemaphore(value: self.capacity)

    // find the next power of 2 that is >= self.capacity
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.allocate(capacity: mask+1)

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
      head += 1
      buffer.advanced(by: head&mask).deinitialize()
      empty.signal()
    }
    buffer.deallocate(capacity: mask+1)
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
      filled.signal()
      empty.signal()
    }
  }

  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    - parameter element: the new element to be added to the channel.
  */

  @discardableResult
  final override func put(_ newElement: T) -> Bool
  {
    if closed != 0 { return false }

    empty.wait()

    if closed == 0
    {
      let newtail = OSAtomicIncrementLongBarrier(&tail)
      buffer.advanced(by: newtail&mask).initialize(to: newElement)

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

    - returns: the oldest element from the channel.
  */

  final override func get() -> T?
  {
    if closed != 0 && (tail &- head) <= 0 { return nil }

    filled.wait()

    let newhead = OSAtomicIncrementLongBarrier(&head)
    if (tail &- newhead) >= 0
    {
      let element = buffer.advanced(by: newhead&mask).move()

      empty.signal()
      return element
    }
    else
    {
      // assert(closed != 0, #function)
      _ = OSAtomicDecrementLongBarrier(&head)
      filled.signal()
      return nil
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(_ selection: Selection, newElement: T) -> Bool
  {
    // the `empty` semaphore has already been decremented for this operation.
    let newtail = OSAtomicIncrementLongBarrier(&tail)
    if closed == 0 && newtail &- head <= capacity
    {
      buffer.advanced(by: newtail&mask).initialize(to: newElement)

      filled.signal()
      return true
    }
    else
    { // This should be very rare. The channel would have to have
      // gotten closed in between the calls to selectPut() and insert().
      _ = OSAtomicDecrementLongBarrier(&tail)
      empty.signal()
      return false
    }
  }

  override func selectPut(_ select: ChannelSemaphore, selection: Selection)
  {
    empty.notify { [weak self] in
      guard let this = self else { return }

      OSMemoryBarrier()
      if this.closed == 0
      {
        if select.setState(.select)
        {
          select.selection = selection
          select.signal()
        }
        else
        {
          this.empty.signal()
        }
        return
      }

      if select.setState(.invalidated)
      {
        select.signal()
      }
      this.empty.signal()
    }
  }

  override func extract(_ selection: Selection) -> T?
  {
    // the `filled` semaphore has already been decremented for this operation.
    let newhead = OSAtomicIncrementLongBarrier(&head)
    if (tail &- newhead) >= 0
    {
      let element = buffer.advanced(by: newhead&mask).move()

      empty.signal()
      return element
    }
    else
    { // This should be very rare. The channel would have to have
      // gotten closed in between the calls to selectGet() and extract().
      // assert(closed != 0, #function)
      _ = OSAtomicDecrementLongBarrier(&head)
      filled.signal()
      return nil
    }
  }

  override func selectGet(_ select: ChannelSemaphore, selection: Selection)
  {
    filled.notify { [weak self] in
      guard let this = self else { return }

      OSMemoryBarrier()
      if this.tail &- this.head > 0
      {
        if select.setState(.select)
        {
          select.selection = selection
          select.signal()
        }
        else
        {
          this.filled.signal()
        }
        return
      }

      // assert(this.closed != 0, #function)
      if select.setState(.invalidated)
      {
        select.signal()
      }
      this.filled.signal()
    }
  }
}

@inline(__always) private func OSAtomicIncrementLongBarrier(_ pointer: UnsafeMutablePointer<Int>) -> Int
{
  #if arch(x86_64) || arch(arm64) // 64-bit architecture
    return Int(OSAtomicIncrement64Barrier(pointer.withMemoryRebound(to: Int64.self, capacity: 1, { $0 })))
  #else // 32-bit architecture
    return Int(OSAtomicIncrement32Barrier(UnsafeMutablePointer<Int32>(pointer)))
  #endif
}

@inline(__always) private func OSAtomicDecrementLongBarrier(_ pointer: UnsafeMutablePointer<Int>) -> Int
{
  #if arch(x86_64) || arch(arm64) // 64-bit architecture
    return Int(OSAtomicDecrement64Barrier(pointer.withMemoryRebound(to: Int64.self, capacity: 1, { $0 })))
  #else // 32-bit architecture
    return Int(OSAtomicDecrement32Barrier(UnsafeMutablePointer<Int32>(pointer)))
  #endif
}
