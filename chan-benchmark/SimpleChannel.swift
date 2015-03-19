//
//  SimpleChannel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-08.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

/**
  The simplest single-element buffered channel that can
  fulfill the contract of ChannelType.
*/

public class SimpleChannel: ChannelType
{
  private var element: Int = 0
  private var head = 0
  private var tail = 0

  private let filled = dispatch_semaphore_create(0)!
  private let empty =  dispatch_semaphore_create(1)!

  // private var lock = OS_SPINLOCK_INIT

  private var closed = false

  deinit
  {
    if head < tail
    {
      dispatch_semaphore_signal(empty)
    }
  }

  public var isClosed: Bool { return closed }
  public var isEmpty: Bool { return head >= tail }
  public var isFull: Bool { return head < tail }

  public func close()
  {
    if closed { return }

    // OSSpinLockLock(&lock)
    closed = true
    // OSSpinLockUnlock(&lock)

    dispatch_semaphore_signal(empty)
    dispatch_semaphore_signal(filled)
  }

  public func put(newElement: Int) -> Bool
  {
    if closed { return false }

    dispatch_semaphore_wait(empty, DISPATCH_TIME_FOREVER)
    // OSSpinLockLock(&lock)

    if closed
    {
      // OSSpinLockUnlock(&lock)
      dispatch_semaphore_signal(empty)
      return false
    }

    element = newElement
    tail++

    // OSSpinLockUnlock(&lock)
    dispatch_semaphore_signal(filled)

    return true
  }

  public func get() -> Int?
  {
    if closed && head >= tail { return nil }

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)
    // OSSpinLockLock(&lock)

    if head < tail
    {
      let e = element
      head++

      // OSSpinLockUnlock(&lock)
      dispatch_semaphore_signal(empty)
      return e
    }
    else
    {
      assert(closed, __FUNCTION__)
      // OSSpinLockUnlock(&lock)
      dispatch_semaphore_signal(filled)
      return nil
    }
  }
}
