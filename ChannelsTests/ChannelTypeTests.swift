//
//  ChannelTypeTests.swift
//  ChannelTypeTests
//
//  Created by Guillaume Lessard on 2014-12-14.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

@testable import Channels

class ChannelTypeTests: XCTestCase
{
  var id: String { return "SimpleChannel" }

  var performanceTestIterations: Int { return 60_000 }

  var buflen: Int { return 1 }

  func InstantiateTestChannel() -> (Sender<Int>, Receiver<Int>)
  {
    let c = SimpleChannel()
    return (Sender(channelType: c), Receiver(channelType: c))
  }

  /**
    Sequentially send, then receive on the same thread.
  */

  func testSendReceive()
  {
    let (tx, rx) = InstantiateTestChannel()
    XCTAssert(rx.isEmpty)

    let value = Int(arc4random() & 0x7fffffff)
    tx <- value
    let result = <-rx

    XCTAssert(value == result, "Wrong value received from channel " + id)
  }

  /**
    Launch asynchronous receive tasks ahead of launching a send task,
    then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let (tx, rx) = InstantiateTestChannel()
    let expectations = 3

    var valrecd = Int(arc4random() & 0x7fffffff)
    for i in 0..<expectations
    {
      let expectation = expectationWithDescription(id + " blocked Receive #\(i), verified reception")
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(arc4random_uniform(50_000))),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
          while let v = <-rx
          {
            valrecd = v
          }
          expectation.fulfill()
      }
    }

    var valsent = Int(arc4random() & 0x7fffffff)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      valsent = Int(arc4random() & 0x7fffffff)
      tx <- valsent
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in " + id)
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let (tx, rx) = InstantiateTestChannel()
    let expectation = expectationWithDescription(id + " blocked Send, verified reception")

    var valsent = Int(arc4random() & 0x7fffffff)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      for i in 0..<self.buflen
      {
        tx <- i
      }
      XCTAssert(tx.isFull)
      valsent = Int(arc4random() & 0x7fffffff)
      tx <- valsent
      tx.close()
    }

    var valrecd = Int(arc4random() & 0x7fffffff)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      for (_,v) in rx.enumerate()
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in " + id)
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let (_, rx) = InstantiateTestChannel()
    let expectation = expectationWithDescription(id + " Receive, no Sender")

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let _ = <-rx
      {
        XCTFail(self.id + " should not receive anything")
      }
      expectation.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(rx.isClosed == false, self.id + " channel should be open")
      rx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in rx.close() }
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let (tx, _) = InstantiateTestChannel()
    let expectation = expectationWithDescription(id + " Send, no Receiver")

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      for _ in 0...self.buflen
      {
        tx <- 0
      }
      XCTAssert(tx.isFull)
      expectation.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " channel should be open")
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
  }
}
