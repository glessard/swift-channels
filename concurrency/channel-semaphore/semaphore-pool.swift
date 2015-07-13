//
//  semaphore-pool.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-07-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A reuse pool for `semaphore_t` mach ports.
  A mach semaphore (obtained with `semaphore_create`) takes several microseconds to create.
  Without a reuse pool, this cost would be incurred every time a thread needs to stop
  in `QUnbufferedChan`, `QBufferedChan` and `select_chan()`. Reusing reduces the cost to
  much less than 1 microsecond.
*/

struct SemaphorePool
{
  static private let capacity = 256
  static private let buffer = UnsafeMutablePointer<semaphore_t>.alloc(capacity)
  static private var cursor = 0

  static private var lock = OS_SPINLOCK_INIT

  /**
    Return a `semaphore_t` to the reuse pool.
    If the pool is full, the `semaphore_t` will be destroyed.

    - parameter s: A `semaphore_t` to return to the reuse pool.
  */

  static func Return(s: semaphore_t)
  {
    assert(s != 0, "Attempted to return an uninitialized semaphore_t in \(__FUNCTION__)")
    OSSpinLockLock(&lock)
    if cursor < capacity
    {
      buffer[cursor] = s
      cursor += 1 
      OSSpinLockUnlock(&lock)
    }
    else
    {
      OSSpinLockUnlock(&lock)
      semaphore_destroy(mach_task_self_, s)
    }
  }

  /**
    Obtain a `semaphore_t` from the reuse pool.
    The returned `semaphore_t` will have a count of zero.

    - returns: A `semaphore_t` that is currently unused.
  */

  static func Obtain() -> semaphore_t
  {
    OSSpinLockLock(&lock)
    if cursor > 0
    {
      cursor -= 1
      let port = buffer[cursor]
      OSSpinLockUnlock(&lock)

      return port
    }
    else
    {
      OSSpinLockUnlock(&lock)

      var port = semaphore_t()
      let kr = semaphore_create(mach_task_self_, &port, SYNC_POLICY_FIFO, 0)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
      return port
    }
  }
}

@inline(__always) func CAS(o: UInt32, _ n: UInt32, _ p: UnsafeMutablePointer<UInt32>) -> Bool
{
  return OSAtomicCompareAndSwap32Barrier(unsafeBitCast(o, Int32.self), unsafeBitCast(n, Int32.self), UnsafeMutablePointer(p))
}
