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

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(buflen)
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    var (tx, rx) = Channel<UInt32>.Make(buflen)

    ChannelTestSendReceive() //tx, rx)
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
