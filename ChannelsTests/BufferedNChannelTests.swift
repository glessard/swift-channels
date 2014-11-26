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

/**
  Most of the tests in Buffered1ChannelTests cover the N-element case as well,
  since Buffered1Chan and BufferedNChan use most of the same logic.
*/

class BufferedNChannelTests: ChannelTestCase
{
  override var id: String  { return "Buffered(N)" }
  override var buflen: Int { return iterations / 1000 }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    var (tx, rx) = Channel<UInt32>.Make(buflen)

    ChannelTestSendReceive(tx, rx)
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

    var (tx, rx) = Channel<UInt32>.Make(buflen)
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
        XCTAssert(e == values[i], "BufferedNChan")
      }
    }
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
    var (tx, rx) = Channel<UInt32>.Make(buflen)

    ChannelTestBlockedSend(tx, rx, expectation: expectation)
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription(id + " blocked Receive, verified reception")
    var (tx, rx) = Channel<UInt32>.Make(buflen)

    ChannelTestBlockedReceive(tx, rx, expectation: expectation)
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let xp = expectationWithDescription(id + " Send, no Receiver")
    var (tx, _) = Channel<()>.Make(buflen)

    ChannelTestNoReceiver(tx, expectation: xp)
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let xp = expectationWithDescription(id + " Receive, no Sender")
    var (_, rx) = Channel<Int>.Make(buflen)

    ChannelTestNoSender(rx, expectation: xp)
  }

  func testPerformanceNoContention()
  {
    var (tx, rx) = Channel<Int>.Make(buflen)

    ChannelPerformanceNoContention(tx, rx)
  }
  
  func testPerformanceLoopNoContention()
  {
    var (tx, rx) = Channel<Int>.Make(buflen)

    ChannelPerformanceLoopNoContention(tx, rx)
  }
  
  func testPerformanceWithContention()
  {
    var (tx, rx) = Channel<Int>.Make(buflen)

    ChannelPerformanceWithContention(tx, rx)
  }
}
