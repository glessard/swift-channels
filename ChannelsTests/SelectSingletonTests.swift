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

import Channels

class SelectSingletonTests: XCTestCase
{
  var selectableCount: Int { return 10 }

  func MakeChannels() -> [(tx: Sender<Int>, rx: Receiver<Int>)]
  {
    return (0..<selectableCount).map { _ in Channel<Int>.MakeSingleton() }
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
      while let selection = select(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i++ }
        }
      }
      for sender in senders { XCTAssert(sender.isClosed, __FUNCTION__) }
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
          print(message)
          i++
        }
      }
    }
    println()

    XCTAssert(i == selectableCount, "Received \(i) messages; expected \(selectableCount)")
  }

  func testSelectReceivers()
  {
    let channels  = MakeChannels()
    let senders   = channels.map { $0.tx }
    let receivers = channels.map { $0.rx }

    async {
      for (i,sender) in enumerate(senders) { sender <- i }
      for sender in senders { XCTAssert(sender.isClosed, __FUNCTION__) }
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
          print(message)
          i++
        }
      }
    }
    println()

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
      while let selection = select(selectables)
      {
        if let sender = selection.id as? Sender<Int>
        {
          if sender.insert(selection, newElement: i) { i++ }
        }
      }
      for sender in senders { XCTAssert(sender.isClosed, __FUNCTION__) }
    }

    let receiver = merge(receivers)

    var i=0
    while let element = <-receiver
    {
      print(element)
      i++
    }
    println()

    XCTAssert(i == selectableCount, "Received \(i) messages; expected \(selectableCount)")
  }
}
