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

@testable import Channels

class SelectUnbufferedTests: XCTestCase
{
  var selectableCount: Int { return 10 }

  func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in QUnbufferedChan<Int>() }
  }

  func getIterations(sleepInterval: NSTimeInterval) -> Int
  {
    return sleepInterval < 0 ? 60_000 : 100
  }

  func SelectReceiverTest(sleepInterval sleepInterval: NSTimeInterval = -1)
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
        for i in 0..<senders.count
        {
          let sender = senders[i]
          let messages = iterations/senders.count + ((i < iterations%senders.count) ? 1:0)

          dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
            for m in 0..<messages
            {
              sender.send(m)
            }
            sender.close()
          }
        }
      }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
         if let _ = receiver.extract(selection) { i++ }
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


  func SelectSenderTest(sleepInterval sleepInterval: NSTimeInterval = -1)
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

      while let _ = receiver.receive()
      {
        m++
        NSThread.sleepForTimeInterval(sleepInterval)
      }
    }
    else
    {
      let result = Channel<Int>.Make(channels.count)

      let g = dispatch_group_create()!
      let q = dispatch_get_global_queue(qos_class_self(), 0)
      for i in 0..<channels.count
      {
        let receiver = receivers[i]
        dispatch_group_async(g, q) {
          var i = 0
          while let _ = receiver.receive() { i++ }
          result.tx <- i
        }
      }
      dispatch_group_notify(g, q) { result.tx.close() }

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

  private func DoubleSelectTest(sleeper sleeper: Sleeper)
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
        if let _ = receiver.extract(selection)
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

  func testSelectAndCloseReceivers()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { Sender(channelType: $0) }
    let receivers = channels.map { Receiver(channelType: $0) }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000_000),
                   dispatch_get_global_queue(qos_class_self(), 0)) {
        _ in
        for sender in senders { sender.close() }
    }

    let selectables = receivers.map { $0 as Selectable }
    while let selection = select(selectables)
    {
      if selection.id is Receiver<Int>
      {
        XCTFail("Should not return one of our Receivers")
      }
    }
  }

  func testSelectAndCloseSenders()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { Sender(channelType: $0) }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10_000_000),
                   dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      for sender in senders { sender.close() }
    }

    for sender in senders
    { // fill up the buffers so that the select() below will block
      while sender.isFull == false { sender <- 0 }
    }

    let selectables = senders.map { $0 as Selectable }
    while let selection = select(selectables)
    {
      if selection.id is Sender<Int>
      {
        XCTFail("Should not return one of our Senders")
      }
    }
  }
}

class SelectQChanBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in QBufferedChan<Int>(1) }
  }
}

class SelectSChanBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in SBufferedChan<Int>(1) }
  }
}
