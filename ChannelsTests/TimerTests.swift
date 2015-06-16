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
    <-rx1
    XCTAssert(rx1.isClosed)

    let rx2 = Timer(delay: 10_000_000)
    XCTAssert(rx2.isClosed == false)
    _ = rx2.receive()
    XCTAssert(rx2.isClosed)

    let rx3 = Receiver.Wrap(Timer())
    XCTAssert(rx3.isClosed == false)
    <-rx3
    rx3.close()
    XCTAssert(rx3.isClosed)

    let _ = Timer()

    let dt = mach_absolute_time() - start
    XCTAssert(dt > 20_000_000)
  }
}
