//
//  SingletonChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

#if os(OSX)
  @testable import Channels
#elseif os(iOS)
  @testable import Channels_iOS
#endif

class SingletonChannelTests: ChannelsTests
{
  override var id: String { return "Singleton" }
  override var buflen: Int { return 1 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(Chan.MakeSingleton())
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive()
  {
    ChannelTestSendReceive()
  }

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceiveTwice()
  {
    let value =  arc4random()
    let (tx,rx) = Channel.Wrap(SingletonChan(value))
    XCTAssert(rx.isEmpty == false)

    tx <- arc4random()
    tx <- arc4random()
    XCTAssert(tx.isFull)
    let result1 = <-rx
    let result2 = <-rx

    XCTAssert(result1 == value, "Incorrect value obtained from \(id) channel.")
    XCTAssert(result2 == nil, "Non-nil value incorrectly obtained from \(id) channel.")
  }

  /**
    Multiple sends in a random order
  */

  func testMultipleSend()
  {
    let (tx, rx) = InstantiateTestChannel(Int)

    let delay = dispatch_time(DISPATCH_TIME_NOW, 1_000_000)
    for i in 1...10
    {
      dispatch_after(delay, dispatch_get_global_queue(qos_class_self(), 0)) { tx <- i }
    }

    var last = 0
    while let _ = <-rx
    {
      last += 1
    }

    XCTAssert(last == 1, "Incorrect number of messages received from \(id) channel")
  }
  
  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the SingletonChan.
  */

  func testReceiveFirst()
  {
    ChannelTestReceiveFirst()
  }

  /**
    Fulfill the asynchronous 'expectation' after its reference has transited through the SingletonChan.
  */

  func testSendFirst()
  {
    ChannelTestSendFirst()
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
    For singleton channel, this one differs from the general case.
  */

  func testNoReceiver()
  {
    let expectation = expectationWithDescription(id + " Channel Send, no Receiver")
    let (tx, _) = InstantiateTestChannel(Void)

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed == false, self.id + " channel should be open")

      tx <- ()
      tx <- ()

      XCTAssert(tx.isClosed, self.id + " channel should be closed")
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100_000_000), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
      XCTAssert(tx.isClosed, self.id + " channel should be closed")
      expectation.fulfill()
    }

    waitForExpectationsWithTimeout(2.0) { _ in tx.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    ChannelTestNoSender()
  }
}
