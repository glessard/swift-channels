//
//  QChannelsTests.swift
//  concurrency
//
//  Tests for channels based on semaphores and "atomic" queues.
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class QUnbufferedChannelTests: PUnbufferedChannelTests
{
  override var id: String  { return "Queue Unbuffered" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QUnbufferedChan<T>())
  }
}

class QBuffered1ChannelTests: PBuffered1ChannelTests
{
  override var id: String { return "Queue Buffered(1)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QBuffered1Chan<T>())
  }
}

class QBufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String  { return "Queue Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QBufferedNChan<T>(buflen))
  }
}
