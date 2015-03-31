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
  let selectableCount = 10

  func SelectReceiverTest(#buffered: Bool, sleepInterval: NSTimeInterval = -1)
  {
    let iterations = sleepInterval < 0 ? 10_000 : 100

    let channels: [Chan<Int>]
    if buffered
    {
      channels  = map(0..<selectableCount) { _ in Chan<Int>.Make(buffered ? 1 : 0) }
    }
    else
    {
      channels  = Array(count: selectableCount, repeatedValue: Chan<Int>.Make(buffered ? 1 : 0))
    }
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

    async {
      for i in 0..<iterations
      {
        if sleepInterval > 0 { NSThread.sleepForTimeInterval(sleepInterval) }
        let index = Int(arc4random_uniform(UInt32(senders.count)))
        senders[index] <- i
      }
      NSThread.sleepForTimeInterval(sleepInterval > 0 ? sleepInterval : 1e-6)
      for sender in senders { sender.close() }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
         if let message = receiver.extract(selection) { i++ }
      }
    }

    syncprintwait()
    
    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
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


  func SelectSenderTest(#buffered: Bool, sleepInterval: NSTimeInterval = -1)
  {
    let iterations = sleepInterval < 0 ? 10_000 : 100

    let chan     = Chan<Int>.Make(buffered ? 1 : 0)
    let senders  = map(0..<selectableCount) { _ in Sender(chan) }
    let receiver = Receiver(chan)

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while let selection = select(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i)
          {
            i++
            if i >= iterations
            {
              for sender in senders { sender.close() }
            }
          }
        }
      }
    }

    var i=0
    while let element = <-receiver
    {
      i++
      if sleepInterval > 0 { NSThread.sleepForTimeInterval(sleepInterval) }
    }

//    syncprint("\(i) messages received")
    syncprintwait()

    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testPerformanceSelectBufferedSender()
  {
    self.measureBlock {
      self.SelectSenderTest(buffered: true)
    }
  }

  func testSelectBufferedSenderWithSleep()
  {
    SelectSenderTest(buffered: true, sleepInterval: 0.01)
  }

  func testPerformanceSelectUnbufferedSender()
  {
    self.measureBlock {
      self.SelectSenderTest(buffered: false)
    }
  }

  func testSelectUnbufferedSenderWithSleep()
  {
    SelectSenderTest(buffered: false, sleepInterval: 0.01)
  }
}
