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
  func testTimer()
  {
    let start = mach_absolute_time()

    let rx1 = Timer(dispatch_time(DISPATCH_TIME_NOW, 10_000_000))
    XCTAssert(rx1.isClosed == false)
    XCTAssert(rx1.isEmpty)
    <-rx1
    XCTAssert(rx1.isEmpty)
    XCTAssert(rx1.isClosed)
    XCTAssert(rx1.isEmpty)

    let rx2 = Timer(delay: 10_000_000)
    XCTAssert(rx2.isClosed == false)
    _ = rx2.receive()
    XCTAssert(rx2.isClosed)

    let rx3 = Receiver.Wrap(Timer())
    XCTAssert(rx3.isClosed == false)
    <-rx3
    XCTAssert(rx3.isClosed)

    let dt = mach_absolute_time() - start
    XCTAssert(dt > 20_000_000)
  }
}
