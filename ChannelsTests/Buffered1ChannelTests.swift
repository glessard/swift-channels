//
//  Buffered1ChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class Buffered1ChannelTests: UnbufferedChannelTests
{
  override var id: String { return "Buffered(1)" }
  override var buflen: Int { return 1 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(1)
  }

  /**
    Performance test when avoiding thread contention, while keeping the channel at never more than 1 item full.
  */

  func testPerformanceNoContention()
  {
    self.measureBlock() {
      let (tx, rx) = self.InstantiateTestChannel(Int)

      for i in 0..<self.performanceTestIterations
      {
        tx <- i
        let r = <-rx
        // XCTAssert(i == r, "bad transmission in " + self.id)
      }
      tx.close()
    }
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    let (tx, rx) = InstantiateTestChannel(UInt32)

    let value = arc4random()
    tx <- value
    let result = <-rx

    XCTAssert(value == result, "Wrong value received from channel " + id)
  }
}
