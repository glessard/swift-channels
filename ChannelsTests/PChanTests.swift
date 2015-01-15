//
//  PBufferedChannelsTests.swift
//  concurrency
//
//  Tests for the pthread-based buffered channels
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

import Channels

class PBuffered1ChannelTests: BufferedChannelTests
{
  override var id: String { return "pthreads Buffered(1)" }
  override var buflen: Int { return 1 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(PChan.Make(buflen))
  }
}

class PBufferedQChannelTests: BufferedNChannelTests
{
  override var id: String  { return "pthreads Buffered(N-Queue)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(BufferedQChan<T>(buflen))
  }
}

class PBufferedAChannelTests: BufferedNChannelTests
{
  override var id: String { return "pthreads Buffered(N-Array)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(BufferedAChan<T>(buflen))
  }
}

class PUnbufferedChannelTests: UnbufferedChannelTests
{
  override var id: String { return "pthreads Unbuffered" }
  override var buflen: Int { return 0 }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(UnbufferedChan<T>())
  }
}
