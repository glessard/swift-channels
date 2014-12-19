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

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QUnbufferedChan<T>())
  }
}

class QBuffered1ChannelTests: PBuffered1ChannelTests
{
  override var id: String { return "Queue Buffered(1)" }

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(QBuffered1Chan<T>())
  }
}

class QBufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String  { return "Queue Buffered(N)" }

  override func Instantiate<T>(_ bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    if bufferLength < 0
    {
      return Channel.Wrap(QBufferedNChan<T>(buflen))
    }
    else
    {
      return Channel.Wrap(QBufferedNChan<T>(bufferLength))
    }
  }
}
