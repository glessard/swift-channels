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

import Channels

class MergeTests: XCTestCase
{
  let outerloopcount = 60
  let innerloopcount = 60

  func testPerformanceMergeReceiver()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for i in 0..<self.outerloopcount
      {
        var (tx, rx) = Channel<Int>.Make(self.innerloopcount)
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
  
  func testPerformanceRoundRobinMergeReceiver()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for i in 0..<self.outerloopcount
      {
        var (tx, rx) = Channel<Int>.Make(self.innerloopcount)
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
  
  func testPerformanceMergeUnbufferedReceiver()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for i in 0..<self.outerloopcount
      {
        var (tx, rx) = Channel<Int>.Make(0)
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
  
  func testPerformanceRoundRobinMergeUnbufferedReceiver()
  {
    self.measureBlock() {
      var chans = [Receiver<Int>]()
      for i in 0..<self.outerloopcount
      {
        var (tx, rx) = Channel<Int>.Make(0)
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
  
  func testPerformanceMergeChan()
  {
    self.measureBlock() {
      var chans = [Chan<Int>]()
      for i in 0..<self.outerloopcount
      {
        let c = Chan<Int>.Make(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(c)
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

  func testPerformanceRoundRobinMergeChan()
  {
    self.measureBlock() {
      var chans = [Chan<Int>]()
      for i in 0..<self.outerloopcount
      {
        let c = Chan<Int>.Make(self.innerloopcount)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(c)
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

  func testPerformanceMergeUnbufferedChan()
  {
    self.measureBlock() {
      var chans = [Chan<Int>]()
      for i in 0..<self.outerloopcount
      {
        let c = Chan<Int>.Make(0)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(c)
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

  func testPerformanceRoundRobinMergeUnbufferedChan()
  {
    self.measureBlock() {
      var chans = [Chan<Int>]()
      for i in 0..<self.outerloopcount
      {
        let c = Chan<Int>.Make(0)
        async {
          for j in 1...self.innerloopcount { c.put(j) }
          c.close()
        }
        chans.append(c)
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
