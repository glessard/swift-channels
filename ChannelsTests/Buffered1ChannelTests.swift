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

class Buffered1ChannelTests: XCTestCase
{
  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    var (tx,rx) = Channel<UInt32>.Make(1)

    let value =  arc4random()
    tx <- value
    let result = <-rx

    XCTAssert(value == result, "Pass")
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Receive then Send")
    var (tx,rx) = Channel.Make(type: expectation,1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-rx
      {
        x.fulfill()
      }
      else
      {
        XCTFail("buffered receive should have received non-nil element")
      }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- expectation
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testSendFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Send then Receive")
    var (tx, rx) = Channel.Make(type: expectation,1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- expectation
      tx.close()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-rx
      {
        x.fulfill()
      }
      else
      {
        XCTFail("buffered receive should have received non-nil element")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let expectation = expectationWithDescription("Buffered(1) blocked Send, verified reception")
    var (tx, rx) = Channel<UInt32>.Make(1)

    var valsent = arc4random()
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      valsent = arc4random()
      tx <- arc4random() <- valsent
      tx.close()
    }

    var valrecd = arc4random()
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, "Buffered(1) should not be closed")

      while let v = <-rx
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in buffered(1)")
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription("Buffered(1) blocked Receive, verified reception")
    var (tx, rx) = Channel<UInt32>.Make(1)

    var valrecd = arc4random()
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    var valsent = arc4random()
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, "Buffered(1) should not be closed")

      valsent = arc4random()
      tx <- valsent
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in buffered(1)")
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let expectation = expectationWithDescription("Buffered(1) Send, no Receiver")
    var (tx, _) = Channel<()>.Make(1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, "Buffered(1) should not be closed")
      tx <- () <- ()
      expectation.fulfill()

      XCTAssert(tx.isClosed, "Buffered(1) should be closed")
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, "Buffered(1) should not be closed")
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let expectation = expectationWithDescription("Buffered(1) Receive, no Sender")
    var (_, rx) = Channel<Int>.Make(1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        XCTFail("should not receive anything")
      }
      expectation.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(rx.isClosed == false, "Buffered(1) should not be closed")
      rx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; rx.close() }
  }

  func testPerformanceNoContention()
  {
    var (tx, rx) = Channel<Int>.Make(1)

    self.measureBlock() {
      for i in 0..<iterations
      {
        tx <- i
        _ = <-rx
      }
      tx.close()
    }
  }

  func testPerformanceWithContention()
  {
    var (tx, rx) = Channel<Int>.Make(1)

    self.measureBlock() {
      async {
        for i in 0..<iterations
        {
          tx <- i
        }
        tx.close()
      }

      for m in rx { _ = m }
    }
  }
}
