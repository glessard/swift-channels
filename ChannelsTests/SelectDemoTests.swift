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

class SelectDemoTests: XCTestCase
{
  func testSelect()
  {
    let a = Channel<Int>.Make(0)
    let b = Channel<Int>.Make(0)
    let c = Channel<Int>.Make(1)
    let d = Channel<Int>.Make(2)
    let e = Channel<Int>.Make(3)

    let channels = [a,b,c,d,e]

    let iterations = 10000
    async {
      let senders = map(channels) { $0.tx }
      for i in 0..<iterations
      {
        let index = Int(arc4random_uniform(UInt32(senders.count)))
        senders[index] <- index
      }
      for sender in senders { sender.close() }
    }

    var messages = Array(count: channels.count, repeatedValue: 0)
    let selectables = map(channels) { $0.rx as Selectable }
    while let selection = select(selectables)
    {
      switch selection.id
      {
      case let s where s === a.rx:
        if let p = a.rx.extract(selection) { messages[p] += 1 }

      case let s where s === b.rx:
        if let p = b.rx.extract(selection) { messages[p] += 1 }

      case let s where s === c.rx:
        if let p = c.rx.extract(selection) { messages[p] += 1 }

      case let s where s === d.rx:
        if let p = d.rx.extract(selection) { messages[p] += 1 }

      case let s where s === e.rx:
        if let p = e.rx.extract(selection) { messages[p] += 1 }

      default:
        syncprint("Bad selection: \(selection)")
      }
    }

    let i = reduce(messages,0,+)
    syncprint("\(messages), \(i) total messages.")
    syncprintwait()
    
    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testRandomBits()
  {
    let channel = Chan<Bool>.Make(0)

    let sender0 = Sender(channel)
    let sender1 = Sender(channel)

    let receiver = Receiver(channel)

    async {
      for _ in 0..<8
      {
        if let selection = select(sender0, sender1)
        {
          switch selection.id
          {
          case let s where s === sender0:
            sender0.insert(selection, newElement: false)

          case let s where s === sender1:
            sender1.insert(selection, newElement: true)

          default: break
          }
        }
      }
      sender0.close()
    }

    while let b = <-receiver
    {
      print("\(b ? 0:1)")
    }
    println()
  }
}
