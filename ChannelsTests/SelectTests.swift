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
  func SelectReceiverTest(#buffered: Bool, sleepInterval: NSTimeInterval = 0)
  {
    let chanCount = 5
    // careful with 'iterations': there's a maximum thread count.
    let iterations = sleepInterval == 0 ? 1000 : 25

    let channels  = map(0..<chanCount) { _ in Chan<Int>.Make(buffered ? iterations : 0) }
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

    let group = dispatch_group_create()!
    let queue = dispatch_queue_create(nil, nil)
    dispatch_group_async(group, dispatch_get_global_queue(qos_class_self(), 0)) {
      dispatch_apply(iterations, dispatch_get_global_queue(qos_class_self(), 0)) {
        let index = Int(arc4random_uniform(UInt32(senders.count)))
        if sleepInterval > 0 { NSThread.sleepForTimeInterval(NSTimeInterval($0)*sleepInterval) }
        senders[index] <- index
          // syncprint("\(i): sent to \(index)")
      }
    }

    dispatch_group_notify(group, dispatch_get_global_queue(qos_class_self(), 0)) {
      for s in enumerate(senders)
      {
        // syncprint("closing sender \(s.index)")
        s.element.close()
      }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let (selected, selection) = select(selectables)
    {
      if let message: Int = selection.getData()
      {
        i++
      }
    }

    //    syncprint("\(i) messages received")
    syncprintwait()
    
    XCTAssert(i == iterations, "incorrect number of messages received")
  }

  func testPerformanceSelectBufferedReceiver()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: true)
    }
  }

  func testSelectBufferedReceiverWithSleep()
  {
    SelectReceiverTest(buffered: true, sleepInterval: 0.01)
  }

  func testPerformanceSelectUnbufferedReceiver()
  {
    self.measureBlock {
      self.SelectReceiverTest(buffered: false)
    }
  }

  func testSelectUnbufferedReceiverWithSleep()
  {
    SelectReceiverTest(buffered: false, sleepInterval: 0.01)
  }


  func SelectSenderTest(#buffered: Bool, sleepInterval: NSTimeInterval = 0)
  {
    let chanCount = 5
    let iterations = sleepInterval == 0 ? 1000 : 25

    let channels  = map(0..<chanCount) { _ in Chan<Int>.Make(buffered ? 1 : 0) }
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

    let (tx, rx) = Channel<Int>.Make()
    let g = dispatch_group_create()
    for (i, receiver) in enumerate(receivers)
    {
      async(group: g) {
        while let element = <-receiver
        {
          tx <- element
//          syncprint("\(element): received via channel #\(i)")
          if sleepInterval > 0 { NSThread.sleepForTimeInterval(sleepInterval) }
        }
      }
    }

    dispatch_group_notify(g, dispatch_get_global_queue(qos_class_self(), 0)) {
      tx.close()
    }

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while let (selected, selection) = select(selectables)
      {
        if let sender = selection.messageID as? Sender<Int>
        {
          if sender.insert(selection, item: i) { i++ }
        }
        if i >= iterations
        {
          for sender in senders { sender.close() }
        }
      }
    }

    var i=0
    while let element = <-rx
    {
      i++
    }

//    syncprint("\(i) messages received")
    syncprintwait()

    XCTAssert(i == iterations, "incorrect number of messages received")
  }

  func testPerformanceSelectBufferedSender()
  {
    self.measureBlock {
      self.SelectSenderTest(buffered: true)
    }
  }

  func testPerformanceSelectUnbufferedSender()
  {
    self.measureBlock {
      self.SelectSenderTest(buffered: false)
    }
  }

  func testSelectBufferedSenderWithSleep()
  {
    SelectSenderTest(buffered: true, sleepInterval: 0.01)
  }

  func testSelectUnbufferedSenderWithSleep()
  {
    SelectSenderTest(buffered: false, sleepInterval: 0.01)
  }
}
