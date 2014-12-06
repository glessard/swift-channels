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

  init(name: String)
  {
    queue = dispatch_queue_create(name+String(arc4random()), DISPATCH_QUEUE_SERIAL)
  }

  deinit
  {
    // If we get here with a suspended queue, GCD will trigger a crash.
    resume()
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
    }
  }

  /**
    Resume the queue if it is suspended

    Somehow, despite the (conceptually) bulletproof housekeeping, the embedded call to
    dispatch_resume() sometimes crashes when used by gcdUnbufferedChan<T>. Mysterious.
  */

  final func resume()
  {
    if OSAtomicCompareAndSwap32Barrier(Suspended, Transient, &state)
    {
      dispatch_resume(queue)
      state = Running
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
