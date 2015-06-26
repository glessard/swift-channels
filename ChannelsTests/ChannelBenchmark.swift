//
//  ChannelBenchmark.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-23.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

#if os(OSX)
  @testable import Channels
#elseif os(iOS)
  @testable import Channels_iOS
#endif

let iterations = 120_000

class ChannelsBenchmark: XCTestCase
{
  func testBenchQBufferedChan()
  {
    let chan = Channel<Int>.Wrap(QBufferedChan(1))

    let tic = Time()
    for i in 0..<iterations
    {
      chan.tx <- i
      if let _ = <-chan.rx {}
    }
    chan.tx.close()
    let dt = tic.toc
    print("\(dt)\t\t(\(dt/iterations) per message)")
  }

  func testBenchSBufferedChan()
  {
    let chan = Channel<Int>.Wrap(SBufferedChan(1))

    let tic = Time()
    for i in 0..<iterations
    {
      chan.tx <- i
      if let _ = <-chan.rx {}
    }
    chan.tx.close()
    let dt = tic.toc
    print("\(dt)\t\t(\(dt/iterations) per message)")
  }

  func testBenchThreadedQBufferedChan()
  {
    let chan = Channel<Int>.Wrap(QBufferedChan(1))

    let tic = Time()
    async {
      for i in 0..<iterations { chan.tx <- i }
      chan.tx.close()
    }

    while let _ = <-chan.rx {}
    let dt = tic.toc
    print("\(dt)\t\t(\(dt/iterations) per message)")
  }

  func testBenchThreadedSBufferedChan()
  {
    let chan = Channel<Int>.Wrap(SBufferedChan(1))

    let tic = Time()
    async {
      for i in 0..<iterations { chan.tx <- i }
      chan.tx.close()
    }

    while let _ = <-chan.rx {}
    let dt = tic.toc
    print("\(dt)\t\t(\(dt/iterations) per message)")
  }

  func testBenchThreadedUnbufferedChan()
  {
    let chan = Channel<Int>.Make()

    let tic = Time()
    async {
      for i in 0..<iterations { chan.tx <- i }
      chan.tx.close()
    }

    while let _ = <-chan.rx {}
    let dt = tic.toc
    print("\(dt)\t\t(\(dt/iterations) per message)")
  }
}
