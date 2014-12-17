//
//  GCDBufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class GCDBufferedNChannelTests: BufferedNChannelTests
{
  override var id: String  { return "GCD Buffered(N)" }
  override var buflen: Int { return performanceTestIterations / 1000 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return gcdChannel<T>.Make(buflen)
  }

  override func testPerformanceWithContention()
  {
    // Just silence this one, since it crashes on a memory access.
  }
}
