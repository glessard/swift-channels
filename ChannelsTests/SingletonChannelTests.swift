//
//  SingletonChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

@testable import Channels

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
    let (tx, rx) = InstantiateTestChannel(Int.self)

    let delay = DispatchTime.now() + Double(1_000_000) / Double(NSEC_PER_SEC)
    for i in 1...10
    {
      DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self())!).asyncAfter(deadline: delay) { tx <- i }
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
    let expectation = self.expectation(description: id + " Channel Send, no Receiver")
    let (tx, _) = InstantiateTestChannel(Void.self)

    DispatchQueue.global().async {
      XCTAssert(tx.isClosed == false, self.id + " channel should be open")

      tx <- ()
      tx <- ()

      XCTAssert(tx.isClosed, self.id + " channel should be closed")
    }

    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + Double(100_000_000) / Double(NSEC_PER_SEC)) {
      XCTAssert(tx.isClosed, self.id + " channel should be closed")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 2.0) { _ in tx.close() }
  }

  /**
    Block on receive, unblock on channel close
  */

  func testNoSender()
  {
    ChannelTestNoSender()
  }
}
