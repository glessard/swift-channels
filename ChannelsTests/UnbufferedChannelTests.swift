//
//  UnbufferedChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

class UnbufferedChannelTests: ChannelTestCase
{
  override var id: String { return "Unbuffered" }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    let xp = expectationWithDescription(id + " Receive then Send")!
    var (tx, rx) = Channel.Make(type: xp)

    ChannelTestReceiveFirst(tx, rx, expectation: xp)
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testSendFirst()
  {
    let expectation = expectationWithDescription(id + " Send then Receive")!
    var (tx, rx) = Channel.Make(type: expectation)

    ChannelTestSendFirst(tx, rx, expectation: expectation)
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let expectation = expectationWithDescription(id + " Send, verified receive")
    var (tx, rx) = Channel<UInt32>.Make()

    ChannelTestBlockedSend(tx, rx, expectation: expectation)
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription(id + " Receive, with verification")
    var (tx, rx) = Channel<UInt32>.Make()

    ChannelTestBlockedReceive(tx, rx, expectation: expectation)
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let xp = expectationWithDescription(id + " Send, no Receiver")
    var (tx, _) = Channel<()>.Make()

    ChannelTestNoReceiver(tx, expectation: xp)
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let xp = expectationWithDescription(id + " Receive, no Sender")
    var (_, rx) = Channel<Int>.Make()

    ChannelTestNoSender(rx, expectation: xp)
  }

  func testPerformanceWithContention()
  {
    var (tx, rx) = Channel<Int>.Make()

    ChannelPerformanceWithContention(tx, rx)
  }
}