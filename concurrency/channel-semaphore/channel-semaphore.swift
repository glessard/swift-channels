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
        s.currentState = ChannelSemaphoreState.Ready.rawValue
        return s
      }

      // for i in reverse(0..<cursor)
      for var i=cursor-1; i>=0; i--
      {
        if isUniquelyReferencedNonObjC(&buffer[i])
        {
          let s = buffer[i]
          buffer[i] = buffer.advancedBy(cursor).move()
          OSSpinLockUnlock(&lock)
          s.svalue = 0
          s.currentState = ChannelSemaphoreState.Ready.rawValue
          return s
        }
      }
      cursor += 1
    }
    OSSpinLockUnlock(&lock)
    return ChannelSemaphore(value: 0)
  }
}

// MARK: ChannelSemaphoreState

enum ChannelSemaphoreState: Int32
{
case Ready

// Unbuffered channel data
case Pointer

// Select() case
case WaitSelect
case Select
case Invalidated

// End state
case Done
}

final public class ChannelSemaphore
{
  private var svalue: Int32
  private var semp = semaphore_t()

  private var currentState = ChannelSemaphoreState.Ready.rawValue
  private var pointer: UnsafeMutablePointer<Void> = nil
  private var seln: Selection? = nil

  private init(value: Int32)
  {
    svalue = (value > 0) ? value : 0
  }

  private convenience init()
  {
    self.init(value: 0)
  }

  deinit
  {
    let kr = semaphore_destroy(mach_task_self_, semp)
    assert(kr == KERN_SUCCESS, __FUNCTION__)
  }

  final private func initSemaphorePort()
  {
    var semaphore = semaphore_t()
    let kr = semaphore_create(mach_task_self_, &semaphore, SYNC_POLICY_FIFO, 0)
    assert(kr == KERN_SUCCESS, __FUNCTION__)

    func atomicAssignPort(port: semaphore_t, assignee: UnsafeMutablePointer<Void>) -> Bool
    { // succeed only if 'semp' is still zero
      return OSAtomicCompareAndSwap32Barrier(0, unsafeBitCast(port, Int32.self),
                                             UnsafeMutablePointer<Int32>(assignee))
    }

    if !atomicAssignPort(semaphore, &semp)
    { // another initialization attempt succeeded concurrently. Don't leak the port; return it.
      let kr = semaphore_destroy(mach_task_self_, semaphore)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }

  var rawState: Int32 { return currentState }
  var state: ChannelSemaphoreState { return ChannelSemaphoreState(rawValue: currentState)! }

  func setState(newState: ChannelSemaphoreState) -> Bool
  {
    switch newState
    {
    case .Pointer, .WaitSelect:
      return OSAtomicCompareAndSwap32Barrier(ChannelSemaphoreState.Ready.rawValue, newState.rawValue, &currentState)

    case .Select, .Invalidated:
      return OSAtomicCompareAndSwap32Barrier(ChannelSemaphoreState.WaitSelect.rawValue, newState.rawValue, &currentState)

    case .Done:
      currentState = ChannelSemaphoreState.Done.rawValue
      OSMemoryBarrier()
      return true

    default:
      return false
    }
  }

  func setPointer<T>(p: UnsafeMutablePointer<T>) -> Bool
  {
    if setState(.Pointer)
    {
      pointer = UnsafeMutablePointer<Void>(p)
      return true
    }
    return false
  }

  func getPointer<T>() -> UnsafeMutablePointer<T>
  {
    if currentState == ChannelSemaphoreState.Pointer.rawValue
    {
      return UnsafeMutablePointer<T>(pointer)
    }
    return nil
  }

  var selection: Selection? {
    get { return seln }
    set { if currentState == ChannelSemaphoreState.Select.rawValue { seln = newValue } }
  }

  func signal() -> Bool
  {
    if OSAtomicIncrement32Barrier(&svalue) <= 0
    {
      while semp == 0
      { // if svalue was previously less than zero, there must be a wait() call
        // currently in the process of initializing semp.
        NSThread.sleepForTimeInterval(1e-10)
      }

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
