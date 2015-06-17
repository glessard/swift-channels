//
//  MergeTest.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-01-15.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

@testable import Channels

class MergeTests: XCTestCase
{
  let outerloopcount = 10
  let innerloopcount = 10_000

  func testPerformanceMerge()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let c = SBufferedChan<Int>(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(Receiver(c))
      }

      let c = chans.merge()

      var total = 0
      while let _ = c.receive()
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceMergeUnbuffered()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let c = QUnbufferedChan<Int>()
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(Receiver(c))
      }

      let c = chans.merge()

      var total = 0
      while let _ = c.receive()
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceRoundRobinMerge()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let c = SBufferedChan<Int>(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(Receiver(c))
      }

      let c = mergeRR(chans)

      var total = 0
      while let _ = c.receive()
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceRoundRobinMergeUnbuffered()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let c = QUnbufferedChan<Int>()
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(Receiver(c))
      }

      let c = mergeRR(chans)

      var total = 0
      while let _ = c.receive()
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
}
