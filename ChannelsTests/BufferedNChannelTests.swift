//
//  BufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class BufferedNChannelTests: Buffered1ChannelTests
{
  override var id: String  { return "Buffered(N)" }
  override var buflen: Int { return performanceTestIterations / 1000 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(buflen)
  }

  /**
    Sequential sends and receives on the same thread.
  */

  func testSendReceiveN()
  {
    var values = Array<UInt32>()
    for i in 0..<buflen
    {
      values.append(arc4random_uniform(UInt32.max/2))
    }

    var (tx, rx) = InstantiateTestChannel(UInt32)
    for v in values
    {
      tx <- v
    }

    let selectedValue = Int(arc4random_uniform(UInt32(buflen)))
    var testedValue: UInt32 = UInt32.max

    for i in 0..<buflen
    {
      if let e = <-rx
      {
        XCTAssert(e == values[i], id)
      }
    }
  }
  
  /**
    Performance test when avoiding thread contention. This one fills then empties the channel buffer.
  */

  func testPerformanceLoopNoContention()
  {
    self.measureBlock() {
      let (tx, rx) = self.InstantiateTestChannel(Int)

      for j in 0..<(self.performanceTestIterations/self.buflen)
      {
        for i in 0..<self.buflen { tx <- i }
        for i in 0..<self.buflen { _ = <-rx }
      }
      tx.close()
    }
  }
}
