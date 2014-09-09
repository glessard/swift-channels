//
//  ChannelsPerformanceTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

private let iterations = 100_000
private let buflen = iterations/100

// These are the same as chan-benchmark/main.swift (and chan-benchmark/chan-benchmark.go)

class ChannelsPerformanceTests: XCTestCase
{
  func testPerformanceBuffered1()
  {
    var buffered1 = Chan<Int>.Make(1)

    self.measureBlock() {
      for i in 0..<iterations
      {
        buffered1 <- i
        _ = <-buffered1
      }
      buffered1.close()
    }
  }

  func testPerformanceBufferedN()
  {
    var bufferedN = Chan<Int>.Make(buflen)

    self.measureBlock() {
      for j in 0..<(iterations/buflen)
      {
        for var i=0; i<buflen; i++
        {
          bufferedN <- i
        }

        for var i=0; i<buflen; i++
        {
          _ = <-bufferedN
        }
      }
      bufferedN.close()
    }
  }

  func testPerformanceUnbuffered()
  {
    var unbuffered = Chan<Int>.Make(0)

    self.measureBlock() {
      async {
        for i in 0..<iterations
        {
          unbuffered <- i
        }
        unbuffered.close()
      }

      while let a = <-unbuffered { _ = a }
    }
  }
}