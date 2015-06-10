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
  let outerloopcount = 60
  let innerloopcount = 600

  func testPerformanceGroupMerge()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let (tx, rx) = Channel<Int>.Make(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = mergeGroup(chans)

      var total = 0
      for _ in c
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceDispatchApplyMerge()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let (tx, rx) = Channel<Int>.Make(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = merge(chans)

      var total = 0
      for _ in c
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
        let (tx, rx) = Channel<Int>.Make(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = mergeRR(chans)

      var total = 0
      for _ in c
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceGroupMergeUnbuffered()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let (tx, rx) = Channel<Int>.Make(0)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = mergeGroup(chans)

      var total = 0
      for _ in c
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
  
  func testPerformanceDispatchApplyMergeUnbuffered()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for _ in 0..<self.outerloopcount
      {
        let (tx, rx) = Channel<Int>.Make(0)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = merge(chans)

      var total = 0
      for _ in c
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
        let (tx, rx) = Channel<Int>.Make(0)
        async {
          for j in 1...self.innerloopcount { tx <- j }
          tx.close()
        }
        chans.append(rx)
      }

      let c = mergeRR(chans)

      var total = 0
      for _ in c
      {
        total += 1
      }

      XCTAssert(total == self.outerloopcount*self.innerloopcount, "Incorrect merge in \(__FUNCTION__)")
    }
  }
}
