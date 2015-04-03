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

class SelectUnbufferedTests: XCTestCase
{
  var selectableCount: Int { return 10 }

  func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in Chan<Int>.Make() }
  }

  func getIterations(sleepInterval: NSTimeInterval) -> Int
  {
    return sleepInterval < 0 ? 10_000 : 100
  }

  func SelectReceiverTest(sleepInterval: NSTimeInterval = -1)
  {
    let iterations = getIterations(sleepInterval)

    let channels  = MakeChannels()
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

  func testPerformanceSelectReceiver()
  {
    self.measureBlock {
      self.SelectReceiverTest()
    }
  }

  func testSelectReceiverWithSleep()
  {
    SelectReceiverTest(sleepInterval: 0.01)
  }


  func SelectSenderTest(sleepInterval: NSTimeInterval = -1)
  {
    let iterations = getIterations(sleepInterval)

    let channels  = MakeChannels()
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

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

    let receiver = merge(receivers)

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

  func testPerformanceSelectSender()
  {
    self.measureBlock {
      self.SelectSenderTest()
    }
  }

  func testSelectSenderWithSleep()
  {
    SelectSenderTest(sleepInterval: 0.01)
  }

  private enum Sleeper { case Receiver; case Sender; case None }

  private func DoubleSelectTest(#sleeper: Sleeper)
  {
    let sleepInterval = (sleeper == .None) ? -1.0 : 0.01
    let iterations = getIterations(sleepInterval)

    let channels  = MakeChannels()
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

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
            if sleeper == .Sender { NSThread.sleepForTimeInterval(sleepInterval) }
            if i >= iterations { break }
          }
        }
      }
      for sender in senders { sender.close() }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
        if let message = receiver.extract(selection)
        {
          i++
          if sleeper == .Receiver { NSThread.sleepForTimeInterval(sleepInterval) }
        }
      }
    }

    syncprintwait()

    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testPerformanceDoubleSelect()
  {
    self.measureBlock {
      self.DoubleSelectTest(sleeper: .None)
    }
  }

  func testDoubleSelectSlowGet()
  {
    DoubleSelectTest(sleeper: .Receiver)
  }

  func testDoubleSelectSlowPut()
  {
    DoubleSelectTest(sleeper: .Sender)
  }
}

class SelectBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in Chan<Int>.Make(1) }
  }
}

class SelectSChanBufferedTests: SelectUnbufferedTests
{
  override var selectableCount: Int { return 4 }

  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in SChan<Int>.Make(1) }
  }
}
