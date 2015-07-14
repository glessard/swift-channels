//
//  SemaphoreTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-22.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

#if os(OSX)
  @testable import Channels
#elseif os(iOS)
  @testable import Channels_iOS
#endif

class ChannelSemaphoreTest: XCTestCase
{
  func testChannelSemaphore()
  {
    let s = ChannelSemaphore()

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      s.wait()
    }

    usleep(100)
    XCTAssert(s.signal())
    XCTAssert(s.signal() == false)
  }

  // more needed
}
