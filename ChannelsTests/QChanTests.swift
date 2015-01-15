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

import Channels

class QUnbufferedChannelTests: UnbufferedChannelTests
{
  override var id: String  { return "Queue Unbuffered" }
  override var buflen: Int { return 0 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QChan.Make(0))
  }
}

class QBufferedNChannelTests: BufferedNChannelTests
{
  override var id: String  { return "Queue Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QChan.Make(buflen))
  }
}
