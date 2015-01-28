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
    let chanCount = 5
    // careful with 'iterations': there's a maximum thread count.
    let iterations = 60

    syncprint(__FUNCTION__)

    var senders = [Sender<Int>]()
    var receivers = [Receiver<Int>]()
    for _ in 0..<chanCount
    {
      let (tx, rx) = Channel<Int>.Make(1)
      senders.append(tx)
      receivers.append(rx)
    }

    let group = dispatch_group_create()
    let queue = dispatch_queue_create(nil, nil)
    for i in 0..<iterations
    {
      let index = Int(arc4random_uniform(UInt32(senders.count)))
      async(group: group) {
//        NSThread.sleepForTimeInterval(NSTimeInterval(i)*0.001)
        senders[index] <- index
        syncprint("\(i): sent to \(index)")
      }
    }

    NSThread.sleepForTimeInterval(0.001)
//    dispatch_async(queue) {
    async {
      dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
      for s in enumerate(senders)
      {
        syncprint("closing sender \(s.index)")
        s.element.close()
      }
    }

    var i = 0
    while let (selected, selection) = select(receivers)
    {
      if let message: Int = selection.getData()
      {
          syncprint("\(i): received from \(message)")
          i++
      }
      else
      {
        syncprint("*** received nil message ***")
      }
    }

    syncprint("\(i) messages received")
    syncprintwait()

    XCTAssert(i == iterations, "incorrect number of messages received")
  }
}
