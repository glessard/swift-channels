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
  case wait
  case notify(()->Void)
}

final class SChanSemaphore
{
  var svalue: Int32
  fileprivate let semp: semaphore_t

  fileprivate let waiters = Fast2LockQueue<WaitType>()

  init(value: Int)
  {
    svalue = (value < 0) ? 0 : Int32(min(value, Int(Int32.max)))
    semp = MachSemaphorePool.Obtain()
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
      MachSemaphorePool.Return(semp)
    }
  }

  
  // MARK: Semaphore functionality

  func signal()
  {
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return

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
        case .wait:
          let kr = semaphore_signal(semp)
          precondition(kr == KERN_SUCCESS)
          return

        case .notify(let block):
          #if false // os(OSX)
            return block()
          #else
            return DispatchQueue.global(qos: DispatchQoS.QoSClass.current ?? .default).async(execute: block)
          #endif
        }
      }
    }
  }

  func wait()
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return
    }

    waiters.enqueue(.wait)

    while case let kr = semaphore_wait(semp), kr != KERN_SUCCESS
    {
      guard kr == KERN_ABORTED else { fatalError("Bad response (\(kr)) from semaphore_wait() in \(#function)") }
    }
    return
  }

  func notify(_ block: @escaping () -> Void)
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return block()
    }

    waiters.enqueue(.notify(block))
  }
}
