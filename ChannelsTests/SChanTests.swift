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

#if os(OSX)
  @testable import Channels
#elseif os(iOS)
  @testable import Channels_iOS
#endif

class SBufferedChannelTests: BufferedChannelTests
{
  override var id: String  { return "Semaphore Buffered(N)" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    if buflen > 1
    {
      return Channel.Wrap(SBufferedChan(buflen))
    }
    else
    {
      return Channel.Wrap(SBufferedChan())
    }
  }
}

class SelectSChanBufferedTests: SelectUnbufferedTests
{
  override func MakeChannels() -> [Chan<Int>]
  {
    return (0..<selectableCount).map { _ in SBufferedChan<Int>(1) }
  }
}
