//
//  ShuffleTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Cocoa
import XCTest

class ShuffleTests: XCTestCase
{
  let a = Array(stride(from: -100.0, to: 1e4, by: 1.0))

  func testPerformanceShuffle()
  {
    self.measureBlock() {
      var s = Array(shuffle(self.a))
    }
  }

  func testPerformanceShuffledSequence()
  {
    self.measureBlock() {
      var s = Array(ShuffledSequence(self.a))
    }
  }

  func testPerformanceSequenceOfShuffledSequence()
  {
    self.measureBlock() {
      var s = Array(SequenceOf(ShuffledSequence(self.a)))
    }
  }
}
