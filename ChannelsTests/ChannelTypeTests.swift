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
    return Channel.Wrap(SimpleChannel())
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
      let expectation = self.expectation(withDescription: id + " blocked Receive #\(i), verified reception")
      DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).asyncAfter(deadline: DispatchTime.now() + Double(Int64(arc4random_uniform(50_000))) / Double(NSEC_PER_SEC)) {
          while let v = <-rx
          {
            valrecd = v
          }
          expectation.fulfill()
      }
    }

    var valsent = Int(arc4random() & 0x7fffffff)
    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).asyncAfter(deadline: DispatchTime.now() + Double(100_000_000) / Double(NSEC_PER_SEC)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      valsent = Int(arc4random() & 0x7fffffff)
      tx <- valsent
      tx.close()
    }

    waitForExpectations(withTimeout: 2.0) { _ in tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in " + id)
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func testBlockedSend()
  {
    let (tx, rx) = InstantiateTestChannel()
    let expectation = self.expectation(withDescription: id + " blocked Send, verified reception")

    var valsent = Int(arc4random() & 0x7fffffff)
    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
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
    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).asyncAfter(deadline: DispatchTime.now() + Double(100_000_000) / Double(NSEC_PER_SEC)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      for (_,v) in rx.enumerated()
      {
        valrecd = v
      }
      expectation.fulfill()
    }

    waitForExpectations(withTimeout: 2.0) { _ in tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in " + id)
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    let rx = Receiver(channelType: SimpleChannel())
    let expectation = self.expectation(withDescription: id + " Receive, no Sender")

    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
      while let _ = <-rx
      {
        XCTFail(self.id + " should not receive anything")
      }
      expectation.fulfill()
    }

    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).asyncAfter(deadline: DispatchTime.now() + Double(100_000_000) / Double(NSEC_PER_SEC)) {
      XCTAssert(rx.isClosed == false, self.id + " channel should be open")
      rx.close()
    }

    waitForExpectations(withTimeout: 2.0) { _ in rx.close() }
  }

  /**
    Block on send, unblock on channel close
  */

  func testNoReceiver()
  {
    let tx = Sender(channelType: SimpleChannel())
    let expectation = self.expectation(withDescription: id + " Send, no Receiver")

    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).async {
      for _ in 0...self.buflen
      {
        tx <- 0
      }
      XCTAssert(tx.isFull)
      expectation.fulfill()
    }

    DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default).asyncAfter(deadline: DispatchTime.now() + Double(100_000_000) / Double(NSEC_PER_SEC)) {
      XCTAssert(tx.isClosed == false, self.id + " channel should be open")
      tx.close()
    }

    waitForExpectations(withTimeout: 2.0) { _ in tx.close() }
  }
}
