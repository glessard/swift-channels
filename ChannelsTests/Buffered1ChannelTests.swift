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
    var buffered1 = Chan<UInt32>.Make(1)

    let value =  arc4random()
    buffered1 <- value
    let result = <-buffered1

    XCTAssert(value == result, "Pass")
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Receive then Send")
    var buff1 = Chan.Make(type: expectation,1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-buff1
      {
        x.fulfill()
      }
      else
      {
        XCTFail("buffered receive should have received non-nil element")
      }
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      buff1 <- expectation
      buff1.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testSendFirst()
  {
    let expectation = expectationWithDescription("Buffered(1) Send then Receive")
    var buff1 = Chan.Make(type: expectation,1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      buff1 <- expectation
      buff1.close()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-buff1
      {
        x.fulfill()
      }
      else
      {
        XCTFail("buffered receive should have received non-nil element")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let expectation = expectationWithDescription("Buffered(1) blocked Send, verified reception")
    var buff1 = Chan<UInt32>.Make(1)

    var valsent = arc4random()
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      valsent = arc4random()
      buff1 <- arc4random() <- valsent
      buff1.close()
    }

    var valrecd = arc4random()
    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !buff1.isClosed
      {
        while let v = <-buff1
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

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in buffered(1)")
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription("Buffered(1) blocked Receive, verified reception")
    var buff1 = Chan<UInt32>.Make(1)

    var valrecd = arc4random()
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-buff1
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    var valsent = arc4random()
    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !buff1.isClosed
      {
        valsent = arc4random()
        buff1 <- valsent
        buff1.close()
      }
      else
      {
        XCTFail("Channel should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in buffered(1)")
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let expectation = expectationWithDescription("Buffered(1) Send, no Receiver")
    var buff1 = Chan<()>.Make(1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      buff1 <- () <- ()
      expectation.fulfill()

      // The following should have no effect
      buff1.close()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !buff1.isClosed
      {
        buff1.close()
      }
      else
      {
        XCTFail("Buffered(1) should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let expectation = expectationWithDescription("Buffered(1) Receive, no Sender")
    var buff1 = Chan<Int>.Make(1)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-buff1
      {
        XCTFail("should not receive anything")
      }
      expectation.fulfill()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !buff1.isClosed
      {
        buff1.close()
      }
      else
      {
        XCTFail("Buffered(1) should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; buff1.close() }
  }
}
