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
  private let q = dispatch_get_global_queue(qos_class_self(), 0)

  func testExample1()
  {
    let (sender, receiver) = Channel<Int>.Make()

    dispatch_async(q) {
      for i in 1...5
      {
        sender <- i
        NSThread.sleepForTimeInterval(0.1)
      }
      sender.close()
    }

    while let m = <-receiver
    {
      print(m)
    }
  }

  func testExample2()
  {
    let (sender, receiver) = Channel<Int>.Make()

    dispatch_async(q) {
      dispatch_apply(5, self.q) { sender <- $0+1 }
      sender.close()
    }

    while let m = <-receiver { print(m) }
  }

  func testExampleProcessingPipeline()
  {
    let intReceiver = {
      (limit: Int) -> Receiver<Int> in
      let (tx, rx) = Channel<Int>.Make()
      dispatch_async(self.q) {
        for i in 0..<limit
        {
          NSThread.sleepForTimeInterval(0.01)
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
      dispatch_async(self.q) {
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
      dispatch_async(self.q) {
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
