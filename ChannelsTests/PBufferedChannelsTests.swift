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

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
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

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    if bufferLength < 0
    {
      return Channel.Wrap(BufferedQChan<T>(buflen))
    }
    else
    {
      return Channel.Wrap(BufferedQChan<T>(bufferLength))
    }
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

  /**
    Performance test with thread contention, with minimum buffer.
  */

  func testPerformanceLoopWithSmallBufferContention()
  {
    ChannelPerformanceWithContention(bufferLength: 1)
  }
}

class PABufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String { return "pthreads Buffered(N-Array)" }

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    if bufferLength < 0
    {
      return Channel.Wrap(BufferedAChan<T>(buflen))
    }
    else
    {
      return Channel.Wrap(BufferedAChan<T>(bufferLength))
    }
  }
}
