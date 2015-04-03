//
//  UnbufferedChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

import Channels

class BufferedChannelTests: UnbufferedChannelTests
{
  var singleElementCase = false

  override var buflen: Int {
    if singleElementCase { return 1 }
    else                 { return performanceTestIterations / 1000 }
  }

  /**
    Performance test when avoiding thread contention, while keeping the channel at never more than 1 item full.
  */

  func testPerformanceNoContention()
  {
    ChannelPerformanceNoContention()
  }

  /**
    Sequentially send, then receive on the same thread.
  */

  func testSendReceive()
  {
    ChannelTestSendReceive()
  }

  /**
    Sequential sends and receives on the same thread.
  */

  func testSendReceiveN()
  {
    ChannelTestSendReceiveN()
  }

  /**
    Performance test when avoiding thread contention. This one fills then empties the channel buffer.
  */

  func testPerformanceLoopNoContention()
  {
    ChannelPerformanceLoopNoContention()
  }

  func testPerformanceSingleElementWithContention()
  {
    singleElementCase = true
    ChannelPerformanceWithContention()
    singleElementCase = false
  }
}
