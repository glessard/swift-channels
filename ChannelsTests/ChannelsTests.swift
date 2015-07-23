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

#if os(OSX)
  @testable import Channels
#elseif os(iOS)
  @testable import Channels_iOS
#endif

class ChannelsTests: XCTestCase
{
  var id: String { return "" }

  class var performanceTestIterations: Int {
    #if os(OSX)
      return 60_000
    #elseif os(iOS)
      return 10_000
    #endif
  }

  var buflen: Int { return 1 }

  func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    if buflen > 0
    {
      return Channel.Make(buflen)
    }
    else
    {
      return Channel.Make()
    }
  }

  /**
    Sequentially send, then receive on the same thread.
  */

  func ChannelTestSendReceive()
  {
    let (tx, rx) = InstantiateTestChannel(Int)
    XCTAssert(rx.isEmpty)

    let value = Int(arc4random() & 0x7fffffff)
    tx <- value

    XCTAssert(rx.underestimateCount() >= 0)
    let result = <-rx

    XCTAssert(value == result, "Wrong value received from channel " + id)
  }

  /**
    Sequential sends and receives on the same thread; fill then empty the channel.
  */

  func ChannelTestSendReceiveN()
  {
    var values = Array<Int>()
    for _ in 0..<buflen
    {
      values.append(Int(arc4random() & 0x7fffffff))
    }

    let (tx, rx) = InstantiateTestChannel(Int)
    for v in values
    {
      tx <- v
    }
    XCTAssert(tx.isFull)

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
    let (tx, rx) = InstantiateTestChannel(XCTestExpectation)
    let expectation = expectationWithDescription(id + " Receive then Send")

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
    let (tx, rx) = InstantiateTestChannel(Int)
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
  Launch a send task ahead of launching a receive task. Fulfill the asynchronous
  'expectation' after its reference has transited through the channel.
  */

  func ChannelTestSendFirst()
  {
    let (tx, rx) = InstantiateTestChannel(XCTestExpectation)
    let expectation = expectationWithDescription(id + " Send then Receive")

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
    let (tx, rx) = InstantiateTestChannel(Int)
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

  func ChannelTestNoSender()
  {
    var (_, rx) = InstantiateTestChannel(Int)
    rx = Receiver.Wrap(rx) // because why not

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

  func ChannelTestNoReceiver()
  {
    var (tx, _) = InstantiateTestChannel(Void)
    tx = Sender.Wrap(tx) // because why not

    let expectation = expectationWithDescription(id + " Send, no Receiver")

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      for _ in 0...self.buflen
      {
        tx <- ()
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

  /**
    Performance test when avoiding thread contention, while keeping the channel at never more than 1 item full.
  */

  func ChannelPerformanceNoContention()
  {
    self.measureBlock() {
      let (tx, rx) = self.InstantiateTestChannel(Int)

      for i in 0..<ChannelsTests.performanceTestIterations
      {
        tx <- i
        _ = <-rx
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
      let (tx, rx) = self.InstantiateTestChannel(Int)

      for _ in 0..<(ChannelsTests.performanceTestIterations/self.buflen)
      {
        for i in 0..<self.buflen { tx <- i }
        for _ in 0..<self.buflen { _ = <-rx }
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
      let (tx, rx) = self.InstantiateTestChannel(Int)
      
      async {
        for i in 0..<ChannelsTests.performanceTestIterations
        {
          tx <- i
        }
        tx.close()
      }
      
      var i = 0
      for _ in rx {
        i++
      }
      XCTAssert(i == ChannelsTests.performanceTestIterations, "Too few (\(i)) iterations completed by " + self.id)
    }
  }
}
