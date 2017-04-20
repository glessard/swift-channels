//
//  ChannelsDemoTests.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-03-20.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch
import Foundation.NSThread
import XCTest

@testable import Channels

class ChannelsExamples: XCTestCase
{
  fileprivate let q = DispatchQueue.global(qos: DispatchQoS.QoSClass(rawValue: qos_class_self())!)

  func testExample1()
  {
    let (sender, receiver) = Channel<Int>.Make()

    q.async {
      for i in 1...5
      {
        sender <- i
        Foundation.Thread.sleep(forTimeInterval: 0.1)
      }
      sender.close()
    }

    print("Output: ", terminator: "")
    while let m = <-receiver { print(m, terminator: "") }
    print("")
  }

  func testExample2()
  {
    let (sender, receiver) = Channel<Int>.Make()

    q.async {
      DispatchQueue.concurrentPerform(iterations: 5) { sender <- $0+1 }
      sender.close()
    }

    print("Output: ", terminator: "")
    while let m = <-receiver { print(m, terminator: "") }
    print("")
  }

  func testExampleProcessingPipeline()
  {
    let intReceiver = {
      (limit: Int) -> Receiver<Int> in
      let (tx, rx) = Channel<Int>.Make()
      self.q.async {
        for i in 0..<limit
        {
          Foundation.Thread.sleep(forTimeInterval: 0.01)
          tx <- i
        }
        print("Closing Int sender")
        tx.close()
      }
      return rx
    }(50)

    let doubleReceiver = {
      (r: Receiver<Int>) -> Receiver<Double> in
      let (tx, rx) = Channel<Double>.Make()
      self.q.async {
        while let i = <-r
        {
          if i % 7 == 0 { tx <- sin(Double(i)/100) }
        }
        tx.close()
      }
      return rx
    }(intReceiver)

    let stringReceiver = {
      (r: Receiver<Double>) -> Receiver<String> in
      let (tx, rx) = Channel<String>.Make()
      self.q.async {
        while let d = <-r
        {
          tx <- d.description
        }
        tx.close()
      }
      return rx
    }(doubleReceiver)

    while let s = <-stringReceiver { print(s) }
  }
}
