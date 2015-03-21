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

import Channels

class ChannelsExamples: XCTestCase
{
  func testExample1()
  {
    let (sender, receiver) = Channel<Int>.Make()

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      for i in 1...5
      {
        sender <- i
        NSThread.sleepForTimeInterval(0.1)
      }
      sender.close()
    }

    while let m = <-receiver
    {
      println(m)
    }
  }

  func testExample2()
  {
    let (sender, receiver) = Channel<Int>.Make()

    let q = dispatch_get_global_queue(qos_class_self(), 0)
    dispatch_async(q) {
      dispatch_apply(5, q) { sender <- $0+1 }
      sender.close()
    }

    while let m = <-receiver { println(m) }
  }

  func testExampleProcessingPipeline()
  {
    let (sender, receiver) = Channel<Int>.Make()

    let q = dispatch_get_global_queue(qos_class_self(), 0)

    dispatch_async(q) {
      for i in 1...5
      {
        sender <- i
        NSThread.sleepForTimeInterval(0.1)
      }
      sender.close()
    }

    let doubleReceiver = {
      (r: Receiver<Int>) -> Receiver<Double> in
      let (tx, rx) = Channel<Double>.Make()
      dispatch_async(q) {
        while let i = <-r
        {
          tx <- sin(Double(i)/10)
        }
        tx.close()
      }
      return rx
    }(receiver)

    let stringReceiver = {
      (r: Receiver<Double>) -> Receiver<String> in
      let (tx, rx) = Channel<String>.Make()
      dispatch_async(q) {
        while let d = <-r
        {
          tx <- d.description
        }
        tx.close()
      }
      return rx
    }(doubleReceiver)

    while let s = <-stringReceiver { println(s) }
  }
}
