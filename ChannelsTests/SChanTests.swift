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

import Channels

class SBufferedChannelTests: BufferedNChannelTests
{
  override var id: String  { return "Semaphore Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SChan.Make(buflen))
  }
}

class SSingletonChannelTests: SingletonChannelTests
{
  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SChan.MakeSingleton())
  }
}