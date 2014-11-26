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

class Buffered1ChannelTests: ChannelTestCase
{
  override var id: String { return "Buffered(1)" }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    var (tx,rx) = Channel<UInt32>.Make(1)

    ChannelTestSendReceive(tx, rx)
  }

  /**
    Fulfill an asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    let xp = expectationWithDescription(id + " Receive then Send")!
    var (tx,rx) = Channel.Make(type: xp, 1)

    ChannelTestReceiveFirst(tx, rx, expectation: xp)
  }

  /**
    Fulfill an asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testSendFirst()
  {
    let expectation = expectationWithDescription(id + " Send then Receive")!
    var (tx, rx) = Channel.Make(type: expectation, 1)

    ChannelTestSendFirst(tx, rx, expectation: expectation)
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let expectation = expectationWithDescription(id + "blocked Send, verified reception")
    var (tx, rx) = Channel<UInt32>.Make(1)

    ChannelTestBlockedSend(tx, rx, expectation: expectation)
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription(id + " blocked Receive, verified reception")
    var (tx, rx) = Channel<UInt32>.Make(1)

    ChannelTestBlockedReceive(tx, rx, expectation: expectation)
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let xp = expectationWithDescription(id + " Send, no Receiver")
    var (tx, _) = Channel<()>.Make(1)

    ChannelTestNoReceiver(tx, expectation: xp)
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let xp = expectationWithDescription(id + " Receive, no Sender")
    var (_, rx) = Channel<Int>.Make(1)

    ChannelTestNoSender(rx, expectation: xp)
  }

  func testPerformanceNoContention()
  {
    var (tx, rx) = Channel<Int>.Make(1)

    ChannelPerformanceNoContention(tx, rx)
  }

  func testPerformanceWithContention()
  {
    var (tx, rx) = Channel<Int>.Make(1)

    ChannelPerformanceWithContention(tx, rx)
  }
}
