//
//  SelectSingletonTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-01-15.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin
import Foundation
import XCTest

@testable import Channels

class SelectSingletonTests: XCTestCase
{
  var selectableCount: Int { return 10 }

  func MakeChannels() -> [(tx: Sender<Int>, rx: Receiver<Int>)]
  {
    return (0..<selectableCount).map { _ in Channel.Wrap(SingletonChan<Int>()) }
  }
  
  func testDoubleSelect()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { $0.tx }
    let receivers = channels.map { $0.rx }

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while let selection = select_chan(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i += 1 }
        }
      }
      for sender in senders { XCTAssert(sender.isClosed, #function) }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select_chan(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
        if let message = receiver.extract(selection)
        {
          print(message, terminator: "")
          i += 1
        }
      }
    }
    print("")
    XCTAssert(i == selectableCount, "Received \(i) messages; expected \(selectableCount)")
  }

  func testSelectReceivers()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { $0.tx }
    let receivers = channels.map { $0.rx }

    async {
      for (i,sender) in senders.enumerate() { sender <- i }
      for sender in senders { XCTAssert(sender.isClosed, #function) }
    }

    var i = 0
    // Currently required to avoid a runtime crash:
    let selectables = receivers.map { $0 as Selectable }
    while let selection = select_chan(selectables)
    {
      if let receiver = selection.id as? Receiver<Int>
      {
        if let message = receiver.extract(selection)
        {
          print(message, terminator: "")
          i += 1
        }
      }
    }
    print("")

    XCTAssert(i == selectableCount, "Received \(i) messages; expected \(selectableCount)")
  }
  
  func testSelectSenders()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { $0.tx }
    let receivers = channels.map { $0.rx }

    async {
      var i = 0
      // Currently required to avoid a runtime crash:
      let selectables = senders.map { $0 as Selectable }
      while let selection = select_chan(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i += 1 }
        }
      }
      for sender in senders { XCTAssert(sender.isClosed, #function) }
    }

    let receiver = merge(receivers)

    var i=0
    while let element = <-receiver
    {
      print(element, terminator: "")
      i += 1
    }
    print("")

    XCTAssert(i == selectableCount, "Received \(i) messages; expected \(selectableCount)")
  }
}
