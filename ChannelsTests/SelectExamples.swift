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

class SelectExamples: XCTestCase
{
  func testSelect()
  {
    let a: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(0)
    let b: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(1)
    let c: (tx: Sender<Int>, rx: Receiver<Int>) = Channel.Wrap(SBufferedChan<Int>.Make(1))
    let d: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(2)
    let e: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(5)

    let channels = [a,b,c,d,e]

    let iterations = 10_000
    async {
      let senders = channels.map { $0.tx }
      for _ in 0..<iterations
      {
        let index = Int(arc4random_uniform(UInt32(senders.count)))
        senders[index] <- index
      }
      for sender in senders { sender.close() }
    }

    var messages = Array(repeating: 0, count: channels.count)
    let selectables = channels.map { $0.rx as Selectable }
    while let selection = select_chan(selectables)
    {
      switch selection
      {
      case a.rx:
        if let p = a.rx.extract(selection) { messages[p] += 1 }

      case b.rx:
        if let p = b.rx.extract(selection) { messages[p] += 1 }

      case c.rx:
        if let p = c.rx.extract(selection) { messages[p] += 1 }

      case d.rx:
        if let p = d.rx.extract(selection) { messages[p] += 1 }

      case e.rx:
        if let p = e.rx.extract(selection) { messages[p] += 1 }

      default:
        continue // missed selection
      }
    }

    let i = messages.reduce(0, +)
    syncprint("\(messages), \(i) total messages.")
    syncprintwait()
    
    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testRandomBits()
  {
    let c0: (tx: Sender<Bool>, rx: Receiver<Bool>) = Channel<Bool>.Make(8)
    let c1: (tx: Sender<Bool>, rx: Receiver<Bool>) = Channel<Bool>.Make(8)

    DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self())!).async {
      for _ in 0..<8
      {
        if let selection = select_chan(c0.tx, c1.tx)
        {
          switch selection.id
          {
          case c0.tx:
            c0.tx.insert(selection, newElement: false)

          case c1.tx:
            c1.tx.insert(selection, newElement: true)

          default: continue
          }
        }
      }
      c0.tx.close()
      c1.tx.close()
    }

    let merged = merge(c0.rx, c1.rx)
    while let b = <-merged
    {
      print("\(b ? 0:1)", terminator: "")
    }
    print("")
  }

  func testSendsAndReceives()
  {
    let capacity = 5
    let c: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(capacity)

    var cap = 0
    var count = 0

    while let selection = select_chan([c.tx, c.rx], preventBlocking: false)
    {
      switch selection.id
      {
      case c.tx:
        if c.tx.insert(selection, newElement: count)
        {
          cap += 1
          print(cap, terminator: "")
          count += 1
          if count > 30 { c.tx.close() }
        }
        else
        {
          XCTFail("Attempted to insert into a full channel (probably)")
        }

      case c.rx:
        if let _ = c.rx.extract(selection)
        {
          cap -= 1
          print(cap, terminator: "")
        }
        else
        {
          XCTFail("Attempted to extract from an empty channel (probably)")
        }

      default: continue
      }

      XCTAssert(cap >= 0 && cap <= capacity)
    }
    print("")
  }

  func testNonBlockingSends()
  {
    let c1 = Channel<UInt32>.Make()
    let c2 = Channel<UInt32>.Make()

    var attempts = 0
    DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self())!).async {
      while let selection = select_chan([c1.tx,c2.tx], preventBlocking: true)
      {
        switch selection
        {
        case c1.tx:
          c1.tx.insert(selection, newElement: arc4random())

        case c2.tx:
          c2.tx.insert(selection, newElement: arc4random())

        default: break
        }

        attempts += 1
        guard attempts < 1000 else { break }
        usleep(1)
      }
      c1.tx.close()
      c2.tx.close()
    }

    let merged = merge(c1.rx, c2.rx)

    var messages = 0
    while let _ = <-merged
    {
      messages += 1
      usleep(100)
    }

    print("Sent \(messages) messages in \(attempts) attempts")
  }
}
