//
//  GCDChannelsTests.swift
//  concurrency
//
//  Tests for channels based on Grand Central Dispatch block queues
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class GCDUnbufferedChannelTests: PUnbufferedChannelTests
{
  override var id: String { return "GCD Unbuffered" }
  override var performanceTestIterations: Int { return 1200 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(gcdUnbufferedChan<T>())
  }
}

class GCDBuffered1ChannelTests: PBuffered1ChannelTests
{
  override var id: String { return "GCD Buffered(1)" }
  override var performanceTestIterations: Int { return 1200 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(gcdBuffered1Chan<T>())
  }
}

class GCDSingletonChannelTests: SingletonChannelTests
{
  override var id: String { return "GCD Singleton" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(gcdSingletonChan<T>())
  }
}
