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

@testable import Channels

class SBufferedChannelTests: BufferedChannelTests
{
  override var id: String  { return "Semaphore Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SBufferedChan(buflen))
  }
}
