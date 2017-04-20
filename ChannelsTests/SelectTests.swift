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
    return (0..<selectableCount).map { _ in Chan<Int>.Make() }
  }

  func getIterations(_ sleepInterval: TimeInterval) -> Int
  {
    return sleepInterval < 0 ? ChannelsTests.performanceTestIterations : 100
  }

  func SelectReceiverTest(sleepInterval: TimeInterval = -1)
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
          Foundation.Thread.sleep(forTimeInterval: sleepInterval)
          let index = Int(arc4random_uniform(UInt32(senders.count)))
          senders[index] <- i
        }
        Foundation.Thread.sleep(forTimeInterval: sleepInterval > 0 ? sleepInterval : 1e-6)
        for sender in senders { sender.close() }
      }
      else
      {
        for i in 0..<senders.count
        {
          let sender = senders[i]
          let messages = iterations/senders.count + ((i < iterations%senders.count) ? 1:0)

          DispatchQueue.global(qos: qos_class_self()).async {
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
    while let selection = select_chan(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
         if let _ = receiver.extract(selection) { i += 1 }
      }
    }

    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testPerformanceSelectReceiver()
  {
    self.measure {
      self.SelectReceiverTest()
    }
  }

  func testSelectReceiverWithSleep()
  {
    SelectReceiverTest(sleepInterval: 0.01)
  }


  func SelectSenderTest(sleepInterval: TimeInterval = -1)
  {
    let iterations = getIterations(sleepInterval)

    let channels  = MakeChannels()
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while i < iterations, let selection = select_chan(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i += 1 }
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
        m += 1
        Foundation.Thread.sleep(forTimeInterval: sleepInterval)
      }
    }
    else
    {
      let result = Channel<Int>.Make(channels.count)

      let g = DispatchGroup()
      let q = DispatchQueue.global(qos: qos_class_self())
      for i in 0..<channels.count
      {
        let receiver = receivers[i]
        q.async(group: g) {
          var i = 0
          while let _ = receiver.receive() { i += 1 }
          result.tx <- i
        }
      }
      g.notify(queue: q) { result.tx.close() }

      while let count = <-result.rx { m += count }
    }

    XCTAssert(m == iterations, "Received \(m) messages; expected \(iterations)")
  }

  func testPerformanceSelectSender()
  {
    self.measure {
      self.SelectSenderTest()
    }
  }

  func testSelectSenderWithSleep()
  {
    SelectSenderTest(sleepInterval: 0.01)
  }

  fileprivate enum Sleeper { case receiver; case sender; case none }

  fileprivate func DoubleSelectTest(sleeper: Sleeper)
  {
    let sleepInterval = (sleeper == .none) ? -1.0 : 0.01
    let iterations = getIterations(sleepInterval)

    let channels  = MakeChannels()
    let senders   = channels.map { Sender($0) }
    let receivers = channels.map { Receiver($0) }

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while let selection = select_chan(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i)
          {
            i += 1
            if sleeper == .sender { Foundation.Thread.sleep(forTimeInterval: sleepInterval) }
            if i >= iterations { break }
          }
        }
      }
      for sender in senders { sender.close() }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select_chan(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
        if let _ = receiver.extract(selection)
        {
          i += 1
          if sleeper == .receiver { Foundation.Thread.sleep(forTimeInterval: sleepInterval) }
        }
      }
    }

    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testPerformanceDoubleSelect()
  {
    self.measure {
      self.DoubleSelectTest(sleeper: .none)
    }
  }

  func testDoubleSelectSlowGet()
  {
    DoubleSelectTest(sleeper: .receiver)
  }

  func testDoubleSelectSlowPut()
  {
    DoubleSelectTest(sleeper: .sender)
  }

  func testSelectAndCloseReceivers()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { Sender(channelType: $0) }
    let receivers = channels.map { Receiver(channelType: $0) }

    DispatchQueue.global(qos: qos_class_self()).asyncAfter(deadline: DispatchTime.now() + Double(10_000_000) / Double(NSEC_PER_SEC)) {
        _ in
        for sender in senders { sender.close() }
    }

    let selectables = receivers.map { $0 as Selectable }
    while let selection = select_chan(selectables)
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

    DispatchQueue.global(qos: qos_class_self()).asyncAfter(deadline: DispatchTime.now() + Double(10_000_000) / Double(NSEC_PER_SEC)) {
      _ in
      for sender in senders { sender.close() }
    }

    for sender in senders
    { // fill up the buffers so that the select_chan() below will block
      while sender.isFull == false { sender <- 0 }
    }

    let selectables = senders.map { $0 as Selectable }
    while let selection = select_chan(selectables)
    {
      if selection.id is Sender<Int>
      {
        XCTFail("Should not return one of our Senders")
      }
    }
  }
}

class SelectBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in Chan<Int>.Make(1) }
  }
}
