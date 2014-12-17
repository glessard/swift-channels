//
//  QueueAnythingTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

class QueueAnythingTests: XCTestCase
{
  let performanceTestIterations=100_000

  func testQueue()
  {
    var q = AnythingQueue<Int>()

    for i in 1...10_000
    {
      let r = arc4random_uniform(2)

      XCTAssert(q.realCount() == q.count, "stored element count does not match actual element count")

      if r == 0
      {
        let b = q.count
        q.enqueue(b)
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

    while let e = q.dequeue()
    {
      _ = e
    }
  }

  func testPerformanceQueue()
  {
    let payload = dispatch_semaphore_create(1)!
    var q = AnythingQueue<dispatch_semaphore_t>()

    self.measureBlock() {
      for i in 1...self.performanceTestIterations
      {
        q.enqueue(payload)
      }

      while let e = q.dequeue()
      {
        _ = e
      }
    }
  }

  func testPerformanceQueue2()
  {
    let payload = dispatch_semaphore_create(1)!
    var q = AnythingQueue<dispatch_semaphore_t>()

    self.measureBlock() {
      for i in 1...self.performanceTestIterations
      {
        q.enqueue(payload)
        _ = q.dequeue()
      }
    }
  }

  func testPerformanceQueue3()
  {
    var q = AnythingQueue<dispatch_semaphore_t>()

    self.measureBlock() {
      for i in 1...self.performanceTestIterations
      {
        _ = q.dequeue()
      }
    }
  }
}
