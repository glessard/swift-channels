//
//  BufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

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
