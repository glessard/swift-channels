//
//  BufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

class BufferedNChannelTests: ChannelsTests
{
  override var id: String  { return "Buffered(N)" }
  override var buflen: Int { return performanceTestIterations / 1000 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(buflen)
  }

  /**
    Sequential send, then receive on the same thread.
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
  Fulfill an asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    ChannelTestReceiveFirst()
  }

  /**
  Fulfill an asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testSendFirst()
  {
    ChannelTestSendFirst()
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    ChannelTestBlockedSend()
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    ChannelTestBlockedReceive()
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    ChannelTestNoReceiver()
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    ChannelTestNoSender()
  }


  func testPerformanceNoContention()
  {
    ChannelPerformanceNoContention()
  }
  
  func testPerformanceLoopNoContention()
  {
    ChannelPerformanceLoopNoContention()
  }
  
  func testPerformanceWithContention()
  {
    ChannelPerformanceWithContention()
  }
}
