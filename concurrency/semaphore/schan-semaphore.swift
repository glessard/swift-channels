//
//  Semaphore.swift
//  LightweightSemaphore
//
//  Created by Guillaume Lessard on 2015-04-03.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin.Mach.task
import Dispatch.time

struct SChanSemaphore
{
  private var svalue: Int32
  private var semp = semaphore_t()

  init(value: Int)
  {
    svalue = (value < 0) ? 0 : Int32(min(value, Int(Int32.max)))
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
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return false

    case Int32.min:
      preconditionFailure("Semaphore signaled too many times")

    default: break
    }

    while semp == 0
    { // if svalue was previously less than zero, there must be a wait() call
      // currently in the process of initializing semp.
      usleep(1)
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

    var kr = KERN_ABORTED
    switch timeout
    {
    case let _ where timeout != DISPATCH_TIME_NOW && timeout != DISPATCH_TIME_FOREVER:
      // a timed wait
      while kr == KERN_ABORTED
      {
        let now = mach_absolute_time()*dispatch_time_t(scale.numer)/dispatch_time_t(scale.denom)
        let delta = (timeout > now) ? (timeout - now) : 0
        let tspec = mach_timespec_t(tv_sec: UInt32(delta/NSEC_PER_SEC), tv_nsec: Int32(delta%NSEC_PER_SEC))
        kr = semaphore_timedwait(semp, tspec)
      }
      assert(kr == KERN_SUCCESS || kr == KERN_OPERATION_TIMED_OUT, __FUNCTION__)

      if kr != KERN_OPERATION_TIMED_OUT { break }
      fallthrough

    case DISPATCH_TIME_NOW:
      // will not wait
      while true
      { // check the state of svalue
        let v = OSAtomicAdd32(0, &svalue)
        if v >= 0
        {
          // An intervening call to semaphore_signal() must be canceled.
          // We need to call semaphore_wait() for the accounting to add up.
          fallthrough
        }
        else
        { // re-increment svalue prudently
          if OSAtomicCompareAndSwap32Barrier(v, v+1, &svalue) { return false }
        }
      }

    case DISPATCH_TIME_FOREVER:
      // will wait forever
      while kr == KERN_ABORTED
      {
        kr = semaphore_wait(semp)
      }
      assert(kr == KERN_SUCCESS, __FUNCTION__)

    default: break
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
