//
//  Buffered1ChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

class Buffered1ChannelTests: ChannelsTests
{
  override var id: String { return "Buffered(1)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(1)
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    ChannelTestSendReceive()
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

  func testPerformanceWithContention()
  {
    ChannelPerformanceWithContention()
  }
}
