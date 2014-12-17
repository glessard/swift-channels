//
//  Buffered1ChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class PBuffered1ChannelTests: PUnbufferedChannelTests
{
  override var id: String { return "pthreads Buffered(1)" }
  override var buflen: Int { return 1 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(Buffered1Chan<T>())
  }

  /**
    Performance test when avoiding thread contention, while keeping the channel at never more than 1 item full.
  */

  func testPerformanceNoContention()
  {
    ChannelPerformanceNoContention()
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    ChannelTestSendReceive()
  }
}
