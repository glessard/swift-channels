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
  func SelectReceiverTest(#buffered: Bool, useSelectable: Bool, sleepInterval: NSTimeInterval = 0)
  {
    let chanCount = 5
    // careful with 'iterations': there's a maximum thread count.
    let iterations = 50

    //    syncprint(__FUNCTION__)

    var senders = [Sender<Int>]()
    var receivers = [Receiver<Int>]()
    for _ in 0..<chanCount
    {
      let (tx, rx) = Channel<Int>.Make(buffered ? iterations : 0)
      senders.append(tx)
      receivers.append(rx)
    }

    let group = dispatch_group_create()
    let queue = dispatch_queue_create(nil, nil)
    for i in 0..<iterations
    {
      let index = Int(arc4random_uniform(UInt32(senders.count)))
      async(group: group) {
        if sleepInterval > 0 { NSThread.sleepForTimeInterval(NSTimeInterval(i)*0.01) }
        senders[index] <- index
        //        syncprint("\(i): sent to \(index)")
      }
    }

    NSThread.sleepForTimeInterval(0.001)
    //    dispatch_async(queue) {
    async {
      dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
      for s in enumerate(senders)
      {
        //        syncprint("closing sender \(s.index)")
        s.element.close()
      }
    }

    var i = 0
    if useSelectable
    {
      let selectables = receivers.map { $0 as Selectable }
      while let (selected, selection) = select(selectables)
      {
        if let message: Int = selection.getData()
        {
          i++
        }
      }
    }
    else
    {
      while let (selected, selection) = select(receivers)
      {
        if let message: Int = selection.getData()
        {
          i++
        }
      }
    }

    //    syncprint("\(i) messages received")
    syncprintwait()
    
    XCTAssert(i == iterations, "incorrect number of messages received")
  }

  func testPerformanceSelectBufferedReceiver()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: true, useSelectable: false, sleepInterval: 0)
    }
  }

  func testSelectBufferedReceiverWithWait()
  {
    SelectReceiverTest(buffered: true, useSelectable: false, sleepInterval: 0.01)
  }

  func testPerformanceSelectUnbufferedReceiver()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: false, useSelectable: false, sleepInterval: 0)
    }
  }

  func testSelectUnbufferedReceiverWithWait()
  {
    SelectReceiverTest(buffered: false, useSelectable: false, sleepInterval: 0.01)
  }
  
  func testPerformanceSelectBufferedReceiverSelectable()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: true, useSelectable: true, sleepInterval: 0)
    }
  }

  func testSelectBufferedReceiverSelectableWithWait()
  {
    SelectReceiverTest(buffered: true, useSelectable: true, sleepInterval: 0.01)
  }

  func testPerformanceSelectUnbufferedReceiverSelectable()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: false, useSelectable: true, sleepInterval: 0)
    }
  }

  func testSelectUnbufferedReceiverSelectableWithWait()
  {
    SelectReceiverTest(buffered: false, useSelectable: true, sleepInterval: 0.01)
  }
}
