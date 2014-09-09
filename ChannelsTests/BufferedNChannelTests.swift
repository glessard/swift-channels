//
//  BufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

/**
  Most of the tests in Buffered1ChannelTests cover the N-element case as well,
  since Buffered1Chan and BufferedNChan use most of the same logic.
*/

class BufferedNChannelTests: XCTestCase
{
  private let buflen = 100

  /**
    Sequential send, then receive on the same thread.
  */

  func testSendReceive1()
  {
    var buffered = Chan<UInt32>.Make(buflen)

    let value =  arc4random()
    buffered <- value
    let result = <-buffered

    XCTAssert(value == result, "BufferedNChan")
  }

  /**
    Sequential sends and receives on the same thread.
  */

  func testSendReceiveN()
  {
    var values = Array<UInt32>()
    for i in 0..<buflen
    {
      values.append(arc4random_uniform(UInt32.max/2))
    }

    var bufferedN = Chan<UInt32>.Make(buflen)
    for v in values
    {
      bufferedN <- v
    }

    let selectedValue = Int(arc4random_uniform(UInt32(buflen)))
    var testedValue: UInt32 = UInt32.max

    for i in 0..<buflen
    {
      if let e = <-bufferedN
      {
        XCTAssert(e == values[i], "BufferedNChan")
      }
    }
  }
}
