//
//  PBufferedChannelsTests.swift
//  concurrency
//
//  Tests for the pthread-based buffered channels
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

class PQBufferedNChannelTests: PBuffered1ChannelTests
{
  override var id: String  { return "pthreads Buffered(N-Queue)" }
  override var buflen: Int { return performanceTestIterations / 1000 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(BufferedQChan<T>(buflen))
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
}

class PABufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String { return "pthreads Buffered(N-Array)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(BufferedAChan<T>(buflen))
  }
}
