//
//  semaphorepool.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

struct SemaphorePool
{
  static private let capacity = 256
  static private let buffer = UnsafeMutablePointer<dispatch_semaphore_t>.alloc(capacity)
  static private var cursor = 0

  static private var lock = OS_SPINLOCK_INIT

  static func Return(s: dispatch_semaphore_t)
  {
    OSSpinLockLock(&lock)
    if cursor < capacity
    {
      buffer.advancedBy(cursor).initialize(s)
      cursor += 1
    }
    OSSpinLockUnlock(&lock)
  }

  static func Obtain() -> dispatch_semaphore_t
  {
    OSSpinLockLock(&lock)
    if cursor > 0
    {
      cursor -= 1
      let s = buffer.advancedBy(cursor).move()
      OSSpinLockUnlock(&lock)
      return s
    }
    OSSpinLockUnlock(&lock)
    return dispatch_semaphore_create(0)
  }
}
