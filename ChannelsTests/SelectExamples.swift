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

    var messages = Array(count: channels.count, repeatedValue: 0)
    let selectables = channels.map { $0.rx as Selectable }
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
        continue // missed selection
      }
    }

    let i = messages.reduce(0, combine: +)
    syncprint("\(messages), \(i) total messages.")
    syncprintwait()
    
    XCTAssert(i == iterations, "Received \(i) messages; expected \(iterations)")
  }

  func testRandomBits()
  {
    let c0: (tx: Sender<Bool>, rx: Receiver<Bool>) = Channel<Bool>.Make(8)
    let c1: (tx: Sender<Bool>, rx: Receiver<Bool>) = Channel<Bool>.Make(8)

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      for _ in 0..<8
      {
        if let selection = select(c0.tx, c1.tx)
        {
          switch selection.id
          {
          case let s where s === c0.tx:
            c0.tx.insert(selection, newElement: false)

          case let s where s === c1.tx:
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
      print("\(b ? 0:1)")
    }
    print("")
  }

  func testSendsAndReceives()
  {
    let capacity = 5
    let c: (tx: Sender<Int>, rx: Receiver<Int>) = Channel<Int>.Make(capacity)

    var cap = 0
    var count = 0

    while let selection = select(c.tx, c.rx)
    {
      switch selection.id
      {
      case let s where s === c.tx:
        if c.tx.insert(selection, newElement: count)
        {
          print(++cap, appendNewline: false)
          if ++count > 30 { c.tx.close() }
        }
        else
        {
          XCTFail("Attempted to insert into a full channel (probably)")
        }

      case let s where s === c.rx:
        if let _ = c.rx.extract(selection)
        {
          print(--cap, appendNewline: false)
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
}
