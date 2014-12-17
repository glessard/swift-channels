//
//  GCDSingletonChannelTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-09-09.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import XCTest

class GCDSingletonChannelTests: SingletonChannelTests
{
  override var id: String { return "GCD Singleton" }

  override func InstantiateTestChannel<T>(_: T.Type) -> (Sender<T>, Receiver<T>)
  {
    return Channel.Wrap(gcdSingletonChan<T>())
  }
}
