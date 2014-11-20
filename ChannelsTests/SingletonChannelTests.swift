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

class SingletonChannelTests: XCTestCase
{
  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    var (tx,rx) = SingletonChan<UInt32>.Make()

    let value =  arc4random()
    tx <- value
    let result = <-rx

    XCTAssert(result == value, "Pass")
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceiveTwice()
  {
    var (tx,rx) = SingletonChan<UInt32>.Make()

    let value =  arc4random()
    tx <- value <- value
    let result1 = <-rx
    let result2 = <-rx

    XCTAssert(result1 == value, "Pass")
    XCTAssert(result2 == nil, "Pass")
  }

  /**
    Multiple sends in a random order
  */

  func testMultipleSendAttempts()
  {
    var (tx,rx) = SingletonChan<Int>.Make()

    for i in 1...10
    {
      let delay = dispatch_time(DISPATCH_TIME_NOW, 1000 + Int64(arc4random_uniform(1000)))
      dispatch_after(delay, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
        _ = { tx <- i }()
      }
    }

    var last = -1
    for (i,r) in enumerate(rx)
    {
      last = i
    }

    XCTAssert(last == 0, "Pass")
  }
  
  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the SingletonChan.
  */

  func testReceiveFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Receive then Send")
    var (tx,rx) = SingletonChan.Make(type: expectation)

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

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- expectation
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the SingletonChan.
  */

  func testSendFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Send then Receive")
    var (tx, rx) = SingletonChan.Make(type: expectation)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- expectation
      tx.close()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
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
    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !rx.isClosed
      {
        while let v = <-rx
        {
          valrecd = v
        }
        expectation.fulfill()
      }
      else
      {
        XCTFail("Channel should not be closed")
      }
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
    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !tx.isClosed
      {
        valsent = arc4random()
        tx <- valsent
        tx.close()
      }
      else
      {
        XCTFail("Channel should not be closed")
      }
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
      tx <- () <- ()
      expectation.fulfill()

      // The following should have no effect
      tx.close()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !tx.isClosed
      {
        tx.close()
      }
      else
      {
        XCTFail("Buffered(1) should not be closed")
      }
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

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !rx.isClosed
      {
        rx.close()
      }
      else
      {
        XCTFail("Buffered(1) should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; rx.close() }
  }
}
