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

struct MachSemaphorePool
{
  static fileprivate let capacity = 256
  static fileprivate let buffer = UnsafeMutablePointer<semaphore_t>.allocate(capacity: capacity)
  static fileprivate var cursor = 0

  static fileprivate var lock = OS_SPINLOCK_INIT

  /**
    Return a `semaphore_t` to the reuse pool.
    If the pool is full, the `semaphore_t` will be destroyed.

    - parameter s: A `semaphore_t` to return to the reuse pool.
  */

  static func Return(_ s: semaphore_t)
  {
    precondition(s != 0, "Attempted to return a nonexistent semaphore_t in \(#function)")

    // reset the semaphore's count to zero if it is greater than zero.
    while case let kr = semaphore_timedwait(s, mach_timespec_t(tv_sec: 0,tv_nsec: 0)), kr != KERN_OPERATION_TIMED_OUT
    {
      guard kr == KERN_SUCCESS || kr == KERN_ABORTED else
      { fatalError("\(kr) in \(#function)") }
    }

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
      guard semaphore_create(mach_task_self_, &port, SYNC_POLICY_FIFO, 0) == KERN_SUCCESS
      else { fatalError("Failed to create mach_semaphore port in \(#function)") }
      return port
    }
  }
}

@inline(__always) func CAS(_ o: UInt32, _ n: UInt32, _ p: UnsafeMutablePointer<UInt32>) -> Bool
{
  return p.withMemoryRebound(to: Int32.self, capacity: 1) {
    OSAtomicCompareAndSwap32Barrier(Int32(bitPattern: o), Int32(bitPattern: n), $0)
  }
}
