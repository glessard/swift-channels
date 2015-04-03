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

class PBufferedQChannelTests: BufferedChannelTests
{
  override var id: String  { return "pthreads Buffered(N-Queue)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(PChan.Make(buflen, bufferType: .Queue))
  }
}

class PBufferedBChannelTests: BufferedChannelTests
{
  override var id: String { return "pthreads Buffered(N-UnsafePointer)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(PChan.Make(buflen, bufferType: .Buffer))
  }
}

class PBufferedAChannelTests: BufferedChannelTests
{
  override var id: String { return "pthreads Buffered(N-UnsafePointer)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(PChan.Make(buflen, bufferType: .Array))
  }
}
