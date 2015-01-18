//
//  SelectTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-01-15.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

import Channels

class SelectTests: XCTestCase
{
  func testSelectReceiver()
  {
    let a = Channel<Int>.Make(1)
    let b = Channel<Int>.Make(1)
    let c = Channel<Int>.Make(1)
    let d = Channel<Int>.Make(2)
    let e = Channel<Int>.Make(3)

    let senders = [a.tx, b.tx, c.tx, d.tx, e.tx]

    for s in senders
    {
      s.close()
    }

//    async {
//      for i in 1...1000
//      {
//        let index = Int(arc4random_uniform(UInt32(senders.count)))
//        senders[index] <- index
//      }
//    }

    var i = 0
    while let (selected, selection) = select(a.rx, b.rx, c.rx, d.rx, e.rx)
    {
      i++
    }

    println(i)
  }
}
