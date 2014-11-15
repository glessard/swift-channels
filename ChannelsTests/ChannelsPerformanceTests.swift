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
    var (tx, rx) = Channel<Int>.Make(1)

    self.measureBlock() {
      for i in 0..<iterations
      {
        tx <- i
        _ = <-rx
      }
      tx.close()
    }
  }

  func testPerformanceBufferedNQueue()
  {
    let (send,receive) = Channel<Int>.Make(buflen)

    self.measureBlock() {
      for j in 0..<(iterations/buflen)
      {
        for var i=0; i<buflen; i++
        {
          send <- i
        }

        for var i=0; i<buflen; i++
        {
          _ = <-receive
        }
      }
      send.close()
    }
  }

  func testPerformanceUnbuffered()
  {
    let (send,receive) = Channel<Int>.Make(0)

    self.measureBlock() {
      async {
        for i in 0..<iterations
        {
          send <- i
        }
        send.close()
      }

      while let a = <-receive { _ = a }
    }
  }
}