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

class UnbufferedChannelTests: XCTestCase
{
  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the channel.
  */

  func testReceiveFirst()
  {
    let expectation = expectationWithDescription("Unbuffered Receive then Send")
    var (tx, rx) = Channel.Make(type: expectation)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-rx
      {
        x.fulfill()
      }
      else
      {
        XCTFail("unbuffered receive should have received non-nil element")
      }
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
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
    let expectation = expectationWithDescription("Unbuffered Send then Receive")
    var (tx, rx) = Channel.Make(type: expectation)

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
        XCTFail("unbuffered receive should have received non-nil element")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let expectation = expectationWithDescription("Unbuffered Send, verified receive")
    var (tx, rx) = Channel<UInt32>.Make()

    var valsent = UInt32.max
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      valsent = arc4random()
      tx <- valsent
      tx.close()
    }

    var valrecd = UInt32.max-1
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
        XCTFail("unbuffered should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in unbuffered")
  }

  /**
    Block on receive, then verify the data was transmitted unchanged.
  */

  func testBlockedReceive()
  {
    let expectation = expectationWithDescription("Unbuffered Receive, with verification")
    var (tx, rx) = Channel<UInt32>.Make()

    var valrecd = UInt32.max-1
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    var valsent = UInt32.max
    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !tx.isClosed
      {
        valsent = arc4random()
        tx <- valsent
        tx.close()
      }
      else
      {
        XCTFail("unbuffered should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in unbuffered")
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let expectation = expectationWithDescription("Unbuffered Send, no Receiver")
    var (tx, rx) = Channel<()>.Make()

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- ()
      expectation.fulfill()

      // The following should have no effect
      tx.close()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !rx.isClosed
      {
        rx.close()
      }
      else
      {
        XCTFail("unbuffered should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let expectation = expectationWithDescription("Unbuffered Receive, no Sender")
    var (tx, rx) = Channel<Int>.Make()

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
      {
        XCTFail("should not receive anything")
      }
      expectation.fulfill()
    }

    dispatch_after(1_000_000_000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if !tx.isClosed
      {
        tx.close()
      }
      else
      {
        XCTFail("unbuffered should not be closed")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ = $0; tx.close() }
  }
}