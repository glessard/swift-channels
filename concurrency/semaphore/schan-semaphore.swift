//
//  Semaphore.swift
//  LightweightSemaphore
//
//  Created by Guillaume Lessard on 2015-04-03.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

enum WaitType
{
  case Wait
  case Notify(()->Void)
}

struct SChanSemaphore
{
  var svalue: Int32
  private var semp = semaphore_t()

  private let waiters = Fast2LockQueue()

  init(value: Int)
  {
    svalue = (value < 0) ? 0 : Int32(min(value, Int(Int32.max)))
  }

  init()
  {
    self.init(value: 0)
  }

  // MARK: Kernel port management

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

    while true
    {
      if let waiter = waiters.dequeue()
      {
        switch waiter
        {
        case .Wait:
          while semp == 0
          { // if svalue was previously less than zero, there must be a wait() call
            // currently in the process of initializing semp.
            usleep(1)
            OSMemoryBarrier()
          }
          return semaphore_signal(semp) == KERN_SUCCESS

        case .Notify(let block):
          dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), block)
          return true
        }
      }
    }
  }

  mutating func wait() -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return true
    }

    waiters.enqueue(.Wait)

    if semp == 0 { initSemaphorePort() }

    while true
    {
      switch semaphore_wait(semp)
      {
      case KERN_ABORTED: continue
      case KERN_SUCCESS: return true
      default: preconditionFailure("Bad reply from semaphore_wait() in \(__FUNCTION__)")
      }
    }
  }

  mutating func notify(block: () -> ()) -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      block()
      return true
    }

    waiters.enqueue(.Notify(block))
    return false
  }
}
