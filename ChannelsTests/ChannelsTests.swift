//
//  ChannelsTests.swift
//  ChannelsTests
//
//  Created by Guillaume Lessard on 2014-12-14.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

class ChannelsTests: XCTestCase
{
  var id: String { return "" }

  let performanceTestIterations = 12_000

  var buflen: Int { return 1 }

  func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel<T>.Make(1)
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func ChannelTestSendReceive()
  {
    var (tx, rx) = InstantiateTestChannel(UInt32)

    let value = arc4random()
    tx <- value
    let result = <-rx

    XCTAssert(value == result, "Wrong value received from channel " + id)
  }

  /**
    Sequential sends and receives on the same thread.
  */

  func ChannelTestSendReceiveN()
  {
    var values = Array<UInt32>()
    for i in 0..<buflen
    {
      values.append(arc4random_uniform(UInt32.max/2))
    }

    var (tx, rx) = InstantiateTestChannel(UInt32)
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
        XCTAssert(e == values[i], id)
      }
    }
  }

  /**
    Launch a receive task ahead of launching a send task. Fulfill the asynchronous
    'expectation' after its reference has transited through the channel.
  */

  func ChannelTestReceiveFirst()
  {
    var (tx, rx) = InstantiateTestChannel(XCTestExpectation)
    let expectation = expectationWithDescription(id + " Receive then Send")!

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      if let x = <-rx
      {
        x.fulfill()
      }
      else
      {
        XCTFail(self.id + " receiver should have received non-nil element")
      }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      tx <- expectation
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
  }

  /**
    Launch asynchronous receive tasks ahead of launching a send task,
    then verify the data was transmitted unchanged.
  */

  func ChannelTestBlockedReceive()
  {
    var (tx, rx) = InstantiateTestChannel(UInt32)
    let expectations = 3

    var valrecd = arc4random()
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

    var valsent = arc4random()
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      valsent = arc4random()
      tx <- valsent
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
    XCTAssert(valsent == valrecd, "\(valsent) ≠ \(valrecd) in " + id)
  }

  /**
  Launch a send task ahead of launching a receive task. Fulfill the asynchronous
  'expectation' after its reference has transited through the channel.
  */

  func ChannelTestSendFirst()
  {
    var (tx, rx) = InstantiateTestChannel(XCTestExpectation)
    let expectation = expectationWithDescription(id + " Send then Receive")!

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
        XCTFail(self.id + " receiver should have received non-nil element")
      }
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
  }

  /**
    Block on send, then verify the data was transmitted unchanged.
  */

  func ChannelTestBlockedSend()
  {
    var (tx, rx) = InstantiateTestChannel(Int)
    let expectation = expectationWithDescription(id + " blocked Send, verified reception")

    var valsent = Int(arc4random())
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      for i in 0..<self.buflen
      {
        tx <- i
      }
      valsent = Int(arc4random())
      tx <- valsent
      tx.close()
    }

    var valrecd = Int(arc4random())
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " should not be closed")

      for (i,v) in enumerate(rx)
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

  func ChannelTestNoSender()
  {
    var (_, rx) = InstantiateTestChannel(Int)
    let expectation = expectationWithDescription(id + " Receive, no Sender")

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      while let v = <-rx
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

  func ChannelTestNoReceiver()
  {
    var (tx, _) = InstantiateTestChannel(Void)
    let expectation = expectationWithDescription(id + " Send, no Receiver")

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      for i in 0...self.buflen
      {
        tx <- ()
      }
      expectation.fulfill()
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " channel should be open")
      tx.close()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
  }

  /**
    Performance test when avoiding thread contention, while keeping the channel at never more than 1 item full.
  */

  func ChannelPerformanceNoContention()
  {
    self.measureBlock() {
      var (tx, rx) = self.InstantiateTestChannel(Int)

      for i in 0..<self.performanceTestIterations
      {
        tx <- i
        let r = <-rx
        // XCTAssert(i == r, "bad transmission in " + self.id)
      }
      tx.close()
    }
  }

  /**
    Performance test when avoiding thread contention. This one fills then empties the channel buffer.
  */

  func ChannelPerformanceLoopNoContention()
  {
    self.measureBlock() {
      var (tx, rx) = self.InstantiateTestChannel(Int)

      for j in 0..<(self.performanceTestIterations/self.buflen)
      {
        for i in 0..<self.buflen { tx <- i }
        for i in 0..<self.buflen { _ = <-rx }
      }
      tx.close()
    }
  }
  
  /**
    Performance test with thread contention.
    The 1st thread fills the channel as fast as it can.
    The 2nd thread empties the chanenl as fast as it can.
    Eventually, the 2 threads start to wait for eath other.
  */
  
  func ChannelPerformanceWithContention()
  {
    self.measureBlock() {
      var (tx, rx) = self.InstantiateTestChannel(Int)
      
      async {
        for i in 0..<self.performanceTestIterations
        {
          tx <- i
        }
        tx.close()
      }
      
      var i = 0
      for m in rx {
        i++
      }
      XCTAssert(i == self.performanceTestIterations, "Too few (\(i)) iterations completed by " + self.id)
    }
  }
}
