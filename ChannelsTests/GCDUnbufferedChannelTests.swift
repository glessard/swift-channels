//
//  UnbufferedChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class GCDUnbufferedChannelTests: PUnbufferedChannelTests
{
  override var id: String { return "GCD Unbuffered" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(gcdUnbufferedChan<T>())
  }
}