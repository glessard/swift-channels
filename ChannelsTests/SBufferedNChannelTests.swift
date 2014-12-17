//
//  BufferedNChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-07.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class SBufferedNChannelTests: PQBufferedNChannelTests
{
  override var id: String  { return "Semaphore Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(SBufferedNChan<T>(buflen))
  }
}
