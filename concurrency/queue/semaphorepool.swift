//
//  qchan.swift
//  Channels
//
//  Created by Guillaume Lessard on 2014-12-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

struct SemaphorePool
{
  static let poolq = ObjectQueue<dispatch_semaphore_t>()

  static func enqueue(s: dispatch_semaphore_t)
  {
    poolq.enqueue(s)
  }

  static func dequeue() -> dispatch_semaphore_t
  {
    if poolq.count > 0
    {
      return poolq.dequeue()!
    }

    return dispatch_semaphore_create(0)!
  }
}
