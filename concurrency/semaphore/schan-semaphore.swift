//
//  Semaphore.swift
//  LightweightSemaphore
//
//  Created by Guillaume Lessard on 2015-04-03.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin.Mach
import Dispatch.time
import Foundation.NSThread

struct SChanSemaphore
{
  private var svalue: Int32
  private var semp = semaphore_t()

  init(value: Int32)
  {
    svalue = (value > 0) ? value : 0
    semp = 0
  }

  init()
  {
    self.init(value: 0)
  }

  func destroy()
  {
    if semp != 0
    {
      let kr = semaphore_destroy(mach_task_self_, semp)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }

  mutating private func initSemaphorePort()
  {
    var port = semaphore_t()
    let kr = semaphore_create(mach_task_self_, &port, SYNC_POLICY_FIFO, 0)
    assert(kr == KERN_SUCCESS, __FUNCTION__)

    let success: Bool = { (ptr: UnsafeMutablePointer<UInt32>) -> Bool in
      return OSAtomicCompareAndSwap32Barrier(0, unsafeBitCast(port, Int32.self), UnsafeMutablePointer<Int32>(ptr))
      }(&semp)

    if !success
    {
      let kr = semaphore_destroy(mach_task_self_, port)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }
  

  // MARK: Semaphore functionality

  mutating func signal() -> Bool
  {
    if OSAtomicIncrement32Barrier(&svalue) > 0
    {
      return false
    }

    while semp == 0
    { // if svalue was previously less than zero, there must be a wait() call
      // currently in the process of initializing semp.
      NSThread.sleepForTimeInterval(1e-10)
      OSMemoryBarrier()
    }

    let kr = semaphore_signal(semp)
    assert(kr == KERN_SUCCESS, __FUNCTION__)
    return kr == KERN_SUCCESS
  }

  mutating func wait(timeout: dispatch_time_t) -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return true
    }

    if semp == 0 { initSemaphorePort() }

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

  mutating func wait() -> Bool
  {
    return wait(DISPATCH_TIME_FOREVER)
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