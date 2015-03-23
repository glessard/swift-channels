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

class SelectDualTests: XCTestCase
{
  private enum Sleeper { case Receiver; case Sender; case None }
  
  private func SelectTest(#buffered: Bool, sleeper: Sleeper)
  {
    let selectableCount = 10
    let iterations = (sleeper == .None) ? 10_000 : 100
    let sleepInterval = 0.01

    let channels  = map(0..<selectableCount) { _ in Chan<Int>.Make(buffered ? 1 : 0) }
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

  func testUnbufferedDualSelect()
  {
    SelectTest(buffered: false, sleeper: .None)
  }

  func testBufferedDualSelect()
  {
    SelectTest(buffered: true, sleeper: .None)
  }

  func testUnbufferedSelectGet()
  {
    SelectTest(buffered: false, sleeper: .Sender)
  }

  func testBufferedSelectGet()
  {
    SelectTest(buffered: true, sleeper: .Sender)
  }

  func testUnbufferedSelectPut()
  {
    SelectTest(buffered: false, sleeper: .Receiver)
  }

  func testBufferedSelectPut()
  {
    SelectTest(buffered: true, sleeper: .Receiver)
  }
}
