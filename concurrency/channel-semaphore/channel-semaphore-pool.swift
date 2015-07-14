//
//  channel-semaphore-pool.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Darwin.libkern.OSAtomic

/**
  An object reuse pool for `ChannelSemaphore`.
  A mach semaphore (obtained with `semaphore_create`) takes several microseconds to create.
  Without a reuse pool, this cost would be incurred every time a thread needs to stop
  in `QUnbufferedChan`, `QBufferedChan` and `select_chan()`. Reusing reduces the cost to
  much less than 1 microsecond.
*/

struct SemaphorePool
{
  static private let capacity = 256
  static private let buffer = UnsafeMutablePointer<ChannelSemaphore>.alloc(capacity)
  static private var cursor = 0

  static private var lock = OS_SPINLOCK_INIT

  /**
    Return a `ChannelSemaphore` to the reuse pool.
    - parameter s: A `ChannelSemaphore` to return to the reuse pool.
  */

  static func Return(s: ChannelSemaphore)
  {
    OSSpinLockLock(&lock)
    if cursor < capacity
    {
      buffer.advancedBy(cursor).initialize(s)
      cursor += 1
      // assert(s.svalue == 0, "Non-zero user-space semaphore count of \(s.svalue) in \(__FUNCTION__)")
      // assert(s.seln == nil || s.state == .DoubleSelect, "Unexpectedly non-nil Selection in \(__FUNCTION__)")
      // assert(s.iptr == nil || s.state == .DoubleSelect, "Non-nil pointer \(s.iptr) in \(__FUNCTION__)")
      assert(s.state == .Done || s.state == .DoubleSelect || s.state == .Ready, "State \(s.state) is incorrect")
    }
    OSSpinLockUnlock(&lock)
  }

  /**
    Obtain a `ChannelSemaphore` from the object reuse pool.
    The returned `ChannelSemaphore` will be uniquely referenced.
    - returns: A uniquely-referenced `ChannelSemaphore`.
  */

  static func Obtain() -> ChannelSemaphore
  {
    OSSpinLockLock(&lock)
    if cursor > 0
    {
      cursor -= 1
      for var i=cursor; i>=0; i--
      {
        if isUniquelyReferencedNonObjC(&buffer[i])
        {
          var s = buffer.advancedBy(cursor).move()
          if i < cursor
          {
            swap(&s, &buffer[i])
          }
          OSSpinLockUnlock(&lock)

          // Expected state:
          // s.svalue = 0
          // s.seln = nil
          // s.iptr = nil
          // s.currentState = ChannelSemaphore.State.Ready.rawValue
          guard s.setState(.Ready) else { fatalError("Bad state for a ChannelSemaphore in \(__FUNCTION__)") }
          return s
        }
      }
      cursor += 1
    }
    OSSpinLockUnlock(&lock)
    return ChannelSemaphore()
  }
}
