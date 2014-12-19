//
//  SChannelsTests.swift
//  concurrency
//
//  Tests for channels based on semaphores
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class SBuffered1ChannelTests: PBuffered1ChannelTests
{
  override var id: String { return "Semaphore Buffered(1)" }
  override var buflen: Int { return 1 }

  override func InstantiateTestChannel<T>(_: T.Type, bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SBuffered1Chan<T>())
  }
}

class SBufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String  { return "Semaphore Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type, bufferLength: Int = -1) -> (Sender<T>, Receiver<T>)
  {
    if bufferLength < 0
    {
      return Channel.Wrap(SBufferedNChan<T>(buflen))
    }
    else
    {
      return Channel.Wrap(SBufferedNChan<T>(bufferLength))
    }
  }
}
