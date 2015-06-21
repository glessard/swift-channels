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

@testable import Channels

class QBufferedChannelTests: BufferedChannelTests
{
  override var id: String  { return "Queue Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    if buflen > 1
    {
      return Channel.Wrap(QBufferedChan(buflen))
    }
    else
    {
      return Channel.Wrap(QBufferedChan())
    }
  }
}

class SelectQChanBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in QBufferedChan<Int>(1) }
  }
}
