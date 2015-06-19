//
//  TimeoutTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Foundation
import XCTest

@testable import Channels

class TimeoutTests: XCTestCase
{
  let delay: Int64 = 50_000

  func testTimeout()
  {
    let start = mach_absolute_time()

    let time1 = dispatch_time(DISPATCH_TIME_NOW, delay)
    let rx1 = Timeout(time1)
    XCTAssert(rx1.isEmpty)
    XCTAssert(rx1.isClosed == false)
    <-rx1
    let time2 = dispatch_time(DISPATCH_TIME_NOW, 0)
    XCTAssert(rx1.isClosed)
    XCTAssert(time1 <= time2)

    let rx2 = Timeout(delay: delay)
    XCTAssert(rx2.isClosed == false)
    _ = rx2.receive()
    XCTAssert(rx2.isClosed)

    let rx3 = Receiver.Wrap(Timeout())
    XCTAssert(rx3.isEmpty)
    <-rx3
    rx3.close()
    XCTAssert(rx3.isClosed)

    let dt = mach_absolute_time() - start
    XCTAssert(dt > numericCast(2*delay))
  }

  func testSelectTimeout()
  {
    let count = 10
    let channels = (0..<count).map { _ in Channel<Int>.Make() }
    let selectables = channels.map {
      (tx: Sender<Int>, rx: Receiver<Int>) -> Selectable in
      return (random()&1 == 0) ? tx : rx
    }

    for var i = 0, j = 0; i < 10; j++
    {
      let timer = Timeout(delay: delay)
      if let selection = select(selectables + [timer])
      {
        XCTAssert(j == i)
        switch selection.id
        {
        case let s where s === timer: XCTFail("Timeout never sets the selection")
        case _ as Sender<Int>:        XCTFail("Incorrect selection")
        case _ as Receiver<Int>:      XCTFail("Incorrect selection")
        default: i++
        }
      }
    }
  }
}
