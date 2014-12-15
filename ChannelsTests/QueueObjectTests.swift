//
//  QueueObjectTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

class QueueObjectTests: XCTestCase
{
  func testQueue()
  {
    let payload = dispatch_semaphore_create(1)!
    var q = ObjectQueue<dispatch_semaphore_t>()

    for i in 1...10_000
    {
      let r = arc4random_uniform(2)

      XCTAssert(q.realCount() == q.count, "stored element count does not match actual element count")

      if r == 0
      {
        let b = q.count
        q.enqueue(payload)
        let a = q.count
        XCTAssert(a-b == 1, "element count improperly incremented upon enqueuing")
      }
      else
      {
        let b = q.count
        if b == 0
        {
          XCTAssert(q.dequeue() == nil, "non-nil result from an empty queue")
        }
        else
        {
          if let v = q.dequeue()
          {
            XCTAssert(b-q.count == 1, "element count improperly decremented upon dequeuing")
          }
          else
          {
            XCTFail("nil result returned by a non-empty queue")
          }
        }
      }
    }

    for e in q
    {
      _ = e
    }
  }

  func testPerformanceQueue()
  {
    let payload = dispatch_semaphore_create(1)!
    var q = ObjectQueue<dispatch_semaphore_t>()

    self.measureBlock() {
      for i in 1...100_000
      {
        q.enqueue(payload)
      }

      for e in q
      {
        _ = e
      }
    }
  }
}
