//
//  Buffered1ChannelTests.swift
//  concurrency
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

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SBuffered1Chan<T>())
  }
}
