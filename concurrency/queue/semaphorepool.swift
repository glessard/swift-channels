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
  static let poolq = SemaphoreStack()

  static func enqueue(s: dispatch_semaphore_t)
  {
    if dispatch_get_context(s) == nil
    {
      poolq.enqueue(s)
    }
  }

  static func dequeue() -> dispatch_semaphore_t
  {
    if let semaphore = poolq.dequeue()
    {
      return semaphore
    }

    return dispatch_semaphore_create(0)!
  }
}
