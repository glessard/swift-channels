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
      if sleepInterval > 0
      {
        for i in 0..<iterations
        {
          NSThread.sleepForTimeInterval(sleepInterval)
          let index = Int(arc4random_uniform(UInt32(senders.count)))
          senders[index] <- i
        }
        NSThread.sleepForTimeInterval(sleepInterval > 0 ? sleepInterval : 1e-6)
        for sender in senders { sender.close() }
      }
      else
      {
        dispatch_apply(senders.count, dispatch_get_global_queue(qos_class_self(), 0)) {
          i in
          let messages = iterations/senders.count + ((i < iterations%senders.count) ? 1:0)
          for m in 0..<messages
          {
            senders[i] <- m
          }
        }
        for sender in senders { sender.close() }
      }
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
      while i < iterations, let selection = select(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i++ }
        }
      }
      for sender in senders { sender.close() }
    }

    var m = 0
    if sleepInterval > 0
    {
      let receiver = merge(receivers)

      while let element = <-receiver
      {
        m++
        NSThread.sleepForTimeInterval(sleepInterval)
      }
    }
    else
    {
      let result = Channel<Int>.Make(channels.count)

      let g = dispatch_group_create()!
      for i in 0..<channels.count
      {
        let receiver = receivers[i]
        dispatch_group_async(g, dispatch_get_global_queue(qos_class_self(), 0)) {
          var i = 0
          while let element = <-receiver { i++ }
          result.tx <- i
        }
      }
      dispatch_group_notify(g, dispatch_get_global_queue(qos_class_self(), 0)) { result.tx.close() }

      while let count = <-result.rx { m += count }
    }

    XCTAssert(m == iterations, "Received \(m) messages; expected \(iterations)")
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
  var sleepCase = false

  override var selectableCount: Int {
    if sleepCase { return 3 }
    else { return super.selectableCount }
  }

  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in SChan<Int>.Make(1) }
  }

  override func testPerformanceSelectReceiver()
  {
    XCTFail("Runs out of threads")
  }

  override func testPerformanceDoubleSelect()
  {
    XCTFail("Runs out of threads")
  }

  override func testSelectReceiverWithSleep()
  {
    sleepCase = true
    super.testSelectReceiverWithSleep()
    sleepCase = false
  }

  override func testSelectSenderWithSleep()
  {
    sleepCase = true
    super.testSelectSenderWithSleep()
    sleepCase = false
  }
}
