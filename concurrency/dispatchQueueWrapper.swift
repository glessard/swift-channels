//
//  queueWrapper.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-05.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Foundation
import Dispatch

/**
  Housekeeping help for dispatch_queue_t objects.
  For some reason they don't expose their state at all,
  so we have to do some of it ourselves.
*/

private let Running:   Int32 = 0
private let Suspended: Int32 = 1
private let Transient: Int32 = -1

final class DispatchQueueWrapper
{
  private let queue: dispatch_queue_t
  private var state: Int32 = Running

  private var waiting: Int32 = 0

  private var busy: Int64 = 0

  init(name: String)
  {
    let qname = name // +String(Int(arc4random())+Int(1e9))
    queue = dispatch_queue_create(qname, DISPATCH_QUEUE_SERIAL)
  }

  deinit
  {
    // If we get here with a suspended queue, GCD will trigger a crash.
    resume()

//    if let name = String.fromCString(dispatch_queue_get_label(queue))
//    {
//      println(name + ": \(busy)")
//    }
  }

  /**
    Is the queue running?
  */

  final var isRunning: Bool { return (state == Running) }

  /**
    How many blocks are (known to be) waiting for execution?
  */

  final var Blocked: Int32 { return waiting }

  /**
    Suspend the queue if it is running
  */

  final func suspend()
  {
    if OSAtomicCompareAndSwap32Barrier(Running, Transient, &state)
    {
      dispatch_suspend(queue)
      state = Suspended
      OSMemoryBarrier()
    }
  }

  /**
    Resume the queue if it is suspended
  */

  final func resume()
  {
    if state != Running
    {
      while state == Transient
      {
        // Busy-wait for a very short time
        // A resume() call must succeed in order to avoid deadlocks.
        // A suspend() call can fail: the queue will get another chance
        OSAtomicIncrement64Barrier(&busy) // OSMemoryBarrier()
      }
      if OSAtomicCompareAndSwap32Barrier(Suspended, Transient, &state)
      {
        dispatch_resume(queue)
        state = Running
        OSMemoryBarrier()
      }
    }
  }

  /**
    Synchronously dispatch a block to the queue
  */

  final func mutex(task: () -> ())
  {
      OSAtomicIncrement32Barrier(&self.waiting)

    dispatch_sync(queue) {

      OSAtomicDecrement32Barrier(&self.waiting)
      task()
    }
  }

  /**
    Asynchronously dispatch a block to the queue
  */

  final func async(task: () -> ())
  {
      OSAtomicIncrement32Barrier(&self.waiting)

    dispatch_async(queue) {

      OSAtomicDecrement32Barrier(&self.waiting)
      task()
    }
  }
}
