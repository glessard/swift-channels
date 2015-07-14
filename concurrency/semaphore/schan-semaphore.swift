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

final class SChanSemaphore
{
  var svalue: Int32
  private var semp = semaphore_t()

  private let waiters = Fast2LockQueue()

  init(value: Int)
  {
    svalue = (value < 0) ? 0 : Int32(min(value, Int(Int32.max)))
  }

  convenience init()
  {
    self.init(value: 0)
  }

  // MARK: Kernel port management

  deinit
  {
    if semp != 0
    {
      let kr = semaphore_destroy(mach_task_self_, semp)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }

  private func initSemaphorePort()
  {
    var port = semaphore_t()
    guard case let kr = semaphore_create(mach_task_self_, &port, SYNC_POLICY_FIFO, 0) where kr == KERN_SUCCESS
    else { fatalError("Failed to create semaphore_t port in \(__FUNCTION__)") }

    if CAS(0, port, &semp) == false
    { // another initialization attempt succeeded concurrently. Don't leak the port: destroy it properly.
      let kr = semaphore_destroy(mach_task_self_, port)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }
  
  
  // MARK: Semaphore functionality

  func signal() -> Bool
  {
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return false

    case Int32.min:
      fatalError("Semaphore signaled too many times")

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
          // block()
          return true
        }
      }
    }
  }

  func wait() -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return true
    }

    waiters.enqueue(.Wait)

    if semp == 0 { initSemaphorePort() }

    while case let kr = semaphore_wait(semp) where kr != KERN_SUCCESS
    {
      guard kr == KERN_ABORTED else { fatalError("Bad response (\(kr)) from semaphore_wait() in \(__FUNCTION__)") }
    }
    return true
  }

  func notify(block: () -> Void) -> Bool
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
