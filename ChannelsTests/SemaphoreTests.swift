//
//  SemaphoreTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-22.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import XCTest
import Dispatch

@testable import Channels

class ChannelSemaphoreTest: XCTestCase
{
  func testChannelSemaphore()
  {
    let s = ChannelSemaphore()

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      s.wait()
    }

    usleep(100)
    s.signal()
    s.signal()
    // return the count to zero
    s.wait()
  }

  // more needed
}
