//
//  TimeoutTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Foundation
import XCTest

@testable import Channels

class TimeoutTests: XCTestCase
{
  let delay: Int64 = 50_000
  let scale = { _ -> mach_timebase_info_data_t in
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  func testTimeout()
  {
    let start = mach_absolute_time()*UInt64(scale.numer)/UInt64(scale.denom)

    let time1 = dispatch_time(DISPATCH_TIME_NOW, delay)
    let rx1 = Timeout(time1)
    XCTAssert(rx1.isEmpty)
    XCTAssert(rx1.isClosed == false)
    <-rx1
    let time2 = dispatch_time(DISPATCH_TIME_NOW, 0)
    XCTAssert(rx1.isClosed)
    XCTAssert(time1 <= time2)

    let rx2 = Timeout(delay: delay)
    XCTAssert(rx2.isClosed == false)
    _ = rx2.receive()
    XCTAssert(rx2.isClosed)

    let rx3 = Receiver.Wrap(Timeout())
    XCTAssert(rx3.isEmpty)
    <-rx3
    rx3.close()
    XCTAssert(rx3.isClosed)

    let dt = mach_absolute_time()*UInt64(scale.numer)/UInt64(scale.denom) - start
    XCTAssert(dt > numericCast(2*delay))
  }

  func testSelectTimeout()
  {
    let count = 10
    let channels = (0..<count).map { _ in Channel<Int>.Make() }
    let selectables = channels.map {
      (tx: Sender<Int>, rx: Receiver<Int>) -> Selectable in
      return (random()&1 == 0) ? tx : rx
    }

    var (i,j) = (0,0)
    while i < 10
    {
      let start = mach_absolute_time()*UInt64(scale.numer)/UInt64(scale.denom)
      let timer = Timeout(delay: delay)
      if let selection = select_chan(selectables + [timer])
      {
        XCTAssert(j == i)
        switch selection.id
        {
        case let s where s === timer: XCTFail("Timeout never sets the selection")
        case _ as Sender<Int>:        XCTFail("Incorrect selection")
        case _ as Receiver<Int>:      XCTFail("Incorrect selection")
        default:
          i += 1
          let dt = mach_absolute_time()*UInt64(scale.numer)/UInt64(scale.denom) - start
          XCTAssert(dt > numericCast(delay))
        }
        j += 1
      }
    }
  }
}

class SinkTests: XCTestCase
{
  func testSink()
  {
    let s1 = Sink<Int>()
    XCTAssert(s1.isFull == false)
    XCTAssert(s1.isClosed == false)
    s1 <- 0

    let s2 = Sender.Wrap(s1)
    XCTAssert(s2.isFull == false)
    XCTAssert(s2.isClosed == false)
    s2 <- 0

    s1.close()
  }

  func testSelectSink()
  {
    let k = Sink<Int>()
    let s = [k as Selectable]

    if let selection = select_chan(s) where selection.id === k
    {
      let success = k.insert(selection, newElement: 0)
      XCTAssert(success)
    }
  }
}

class EmptyChanTests: XCTestCase
{
  func testEmptyReceiver()
  {
    let r = Receiver<Int>()
    XCTAssert(r.isEmpty)
    XCTAssert(r.isClosed)
    if let _ = <-r
    {
      XCTFail()
    }

    let s = [r as Selectable]
    if let selection = select_chan(s) where selection.id === r
    {
      XCTFail()
    }

    r.close()
  }

  func testEmptySender()
  {
    let s1 = Sender<Int>()
    XCTAssert(s1.isFull == false)
    XCTAssert(s1.isClosed)
    if s1.send(0)
    {
      XCTFail()
    }

    let s = [s1 as Selectable]
    if let selection = select_chan(s) where selection.id === s1
    {
      XCTFail()
    }
    s1.close()
  }
}
