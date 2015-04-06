//
//  Semaphore.swift
//  LightweightSemaphore
//
//  Created by Guillaume Lessard on 2015-04-03.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin.Mach
import Dispatch.time

struct SemaphorePool
{
  static private let capacity = 256
  static private let buffer = UnsafeMutablePointer<ChannelSemaphore>.alloc(capacity)
  static private var cursor = 0

  static private var lock = OS_SPINLOCK_INIT

  static func Return(s: ChannelSemaphore)
  {
    OSSpinLockLock(&lock)
    if cursor < capacity
    {
      buffer.advancedBy(cursor).initialize(s)
      cursor += 1
    }
    OSSpinLockUnlock(&lock)
  }

  static func Obtain() -> ChannelSemaphore
  {
    OSSpinLockLock(&lock)
    if cursor > 0
    {
      cursor -= 1
      if isUniquelyReferencedNonObjC(&buffer[cursor])
      {
        let s = buffer.advancedBy(cursor).move()
        OSSpinLockUnlock(&lock)
        s.svalue = 0
        s.status = .Empty
        return s
      }
      else
      {
        for var i=cursor-1; i>=0; i--
        {
          if isUniquelyReferencedNonObjC(&buffer[i])
          {
            let s = buffer[i]
            buffer[i] = buffer.advancedBy(cursor).move()
            OSSpinLockUnlock(&lock)
            s.svalue = 0
            s.status = .Empty
            return s
          }
        }
//        if cursor == capacity-1
//        { // clear some pool space
//          let shift = 16
//          // the following line slows things down even if it never gets called.
//          // buffer.assignFrom(buffer.advancedBy(shift), count: capacity-shift)
//          buffer.advancedBy(capacity-16).destroy(16)
//          cursor -= 16
//        }
//        cursor += 1
        buffer.advancedBy(cursor).destroy()
      }
    }
    OSSpinLockUnlock(&lock)
    return ChannelSemaphore(value: 0)
  }
}

enum ChannelSemaphoreStatus
{
case Empty

// Unbuffered channel cases
case Address(UnsafePointer<Void>)
case Pointer(UnsafeMutablePointer<Void>)

case WaitSelect
case Selected //(Selection)
case Invalidated
}

final class ChannelSemaphore
{
  private var svalue: Int32
  private let semp: semaphore_t

  var status = ChannelSemaphoreStatus.Empty

  init(value: Int32)
  {
    svalue = (value > 0) ? value : 0
    var tmpSemp = semaphore_t()
    let kr = semaphore_create(mach_task_self_, &tmpSemp, SYNC_POLICY_FIFO, 0)
    assert(kr == KERN_SUCCESS, __FUNCTION__)
    semp = tmpSemp
  }

  convenience init()
  {
    self.init(value: 0)
  }

  deinit
  {
    let kr = semaphore_destroy(mach_task_self_, semp)
    assert(kr == KERN_SUCCESS, __FUNCTION__)
  }

  func signal() -> Bool
  {
    if OSAtomicIncrement32Barrier(&svalue) <= 0
    {
      let kr = semaphore_signal(semp)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
      return kr == KERN_SUCCESS
    }
    return false
  }

  func wait() -> Bool
  {
    return wait(DISPATCH_TIME_FOREVER)
  }

  func wait(timeout: dispatch_time_t) -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return true
    }

    var kr: kern_return_t
    switch timeout
    {
    case DISPATCH_TIME_NOW: // will not wait
      kr = semaphore_timedwait(semp, mach_timespec_t())
      assert(kr == KERN_SUCCESS || kr == KERN_OPERATION_TIMED_OUT, __FUNCTION__)

    case DISPATCH_TIME_FOREVER: // will wait forever
      do {
        kr = semaphore_wait(semp)
      } while kr == KERN_ABORTED
      assert(kr == KERN_SUCCESS, __FUNCTION__)

    default: // a timed wait
      do {
        let delta = timeoutDelta(timeout)
        let tspec = mach_timespec_t(tv_sec: UInt32(delta/NSEC_PER_SEC), tv_nsec: Int32(delta%NSEC_PER_SEC))
        kr = semaphore_timedwait(semp, tspec)
      } while kr == KERN_ABORTED
      assert(kr == KERN_SUCCESS || kr == KERN_OPERATION_TIMED_OUT, __FUNCTION__)
   }

    if kr == KERN_OPERATION_TIMED_OUT
    {
      OSAtomicIncrement32Barrier(&svalue)
      return false
    }

    return kr == KERN_SUCCESS
  }
}

private var scale: mach_timebase_info = {
  var info = mach_timebase_info(numer: 0, denom: 0)
  mach_timebase_info(&info)
  return info
  }()

// more or less copied from libdispatch/Source/time.c, _dispatch_timeout()

private func timeoutDelta(time: dispatch_time_t) -> dispatch_time_t
{
  switch time
  {
  case DISPATCH_TIME_FOREVER:
    return DISPATCH_TIME_FOREVER

  case 0: // DISPATCH_TIME_NOW
    return 0

  default:
    let now = mach_absolute_time()*dispatch_time_t(scale.numer)/dispatch_time_t(scale.denom)
    return (time > now) ? (time - now) : 0
  }
}
