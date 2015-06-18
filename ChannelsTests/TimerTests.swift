//
//  TimerTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Foundation
import XCTest

@testable import Channels

class TimerTests: XCTestCase
{
  let delay: Int64 = 50_000

  func testTimer()
  {
    let start = mach_absolute_time()

    let time1 = dispatch_time(DISPATCH_TIME_NOW, delay)
    let rx1 = Timer(time1)
    XCTAssert(rx1.isClosed == false)
    <-rx1
    let time2 = dispatch_time(DISPATCH_TIME_NOW, 0)
    XCTAssert(rx1.isClosed)
    XCTAssert(time1 <= time2)

    XCTAssert(rx1.isEmpty)

    let rx2 = Timer(delay: delay)
    XCTAssert(rx2.isClosed == false)
    _ = rx2.receive()
    XCTAssert(rx2.isClosed)

    let rx3 = Receiver.Wrap(Timer())
    <-rx3
    rx3.close()
    XCTAssert(rx3.isClosed)

    let dt = mach_absolute_time() - start
    XCTAssert(dt > numericCast(2*delay))
  }

  func testSelectTimer()
  {
    let count = 10
    let channels = (0..<count).map { _ in Channel<Int>.Make() }
    let selectables = channels.map {
      (tx: Sender<Int>, rx: Receiver<Int>) -> Selectable in
      return (random()&1 == 0) ? tx : rx
    }

    for var i = 0, j = 0; i < 10; j++
    {
      let timer = Timer(delay: delay)
      if let selection = select(selectables + [timer])
      {
        XCTAssert(j == i)
        switch selection.id
        {
        case let s where s === timer: XCTFail("Timer never sets the selection")
        case _ as Sender<Int>:        XCTFail("Incorrect selection")
        case _ as Receiver<Int>:      XCTFail("Incorrect selection")
        default: i++
        }
      }
    }
  }
}
