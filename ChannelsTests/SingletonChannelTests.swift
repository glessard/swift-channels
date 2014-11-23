//
//  Buffered1ChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
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

    XCTAssert(result == value, "Incorrect value obtained from channel.")
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

    XCTAssert(result1 == value, "Incorrect value obtained from channel.")
    XCTAssert(result2 == nil, "Non-nil value incorrectly obtained from channel.")
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

    XCTAssert(last == 0, "Incorrect number of messages received from channel")
  }
  
  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the SingletonChan.
  */

  func testReceiveFirst()
  {
    let expectation = expectationWithDescription("Singleton Channel Receive then Send")
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
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
    let expectation = expectationWithDescription("Singleton Channel Send then Receive")
    var (tx, rx) = SingletonChan.Make(type: expectation)

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
        XCTFail("singleton channel receive should have received non-nil element")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription("Singleton Channel blocked Receive, verified reception")
    var (tx, rx) = Channel<UInt32>.MakeSingleton()

    var valrecd = arc4random()
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        valrecd = v
      }
      XCTAssert(rx.isClosed, "Singleton Channel should be closed after first receive")
      expectation.fulfill()
    }

    var valsent = arc4random()
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !tx.isClosed
      {
        valsent = arc4random()
        tx <- valsent
      }
      else
      {
        XCTFail("Channel should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in Singleton Channel")
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let expectation = expectationWithDescription("Singleton Channel Send, no Receiver")
    var (tx, _) = Channel<()>.MakeSingleton()

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, "Singleton channel should be open")

      tx <- () <- ()
      expectation.fulfill()

      XCTAssert(tx.isClosed, "Singleton channel should be closed")
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed, "Singleton channel should be closed")
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let expectation = expectationWithDescription("Singleton Channel Receive, no Sender")
    var (_, rx) = Channel<Int>.MakeSingleton()

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        XCTFail("should not receive anything")
      }
      expectation.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(rx.isClosed == false, "Singleton channel should be open")
      rx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; rx.close() }
  }
}
