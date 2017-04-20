//
//  SimpleChannel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-08.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

@testable import Channels

/**
  The simplest single-element buffered channel that can
  fulfill the contract of ChannelType.
*/

open class SimpleChannel: ChannelType, SelectableChannelType
{
  fileprivate var element: Int = 0
  fileprivate var head = 0
  fileprivate var tail = 0

  fileprivate let filled = DispatchSemaphore(value: 0)
  fileprivate let empty =  DispatchSemaphore(value: 1)

  fileprivate var closed = false

  deinit
  {
    if head < tail
    {
      empty.signal()
    }
  }

  open var isClosed: Bool { return closed }
  open var isEmpty: Bool { return tail &- head <= 0 }
  open var isFull: Bool { return tail &- head >= 1 }

  open func close()
  {
    if closed { return }

    closed = true

    empty.signal()
    filled.signal()
  }

  open func put(_ newElement: Int) -> Bool
  {
    if closed { return false }

    _ = empty.wait(timeout: DispatchTime.distantFuture)

    if closed
    {
      empty.signal()
      return false
    }

    element = newElement
    tail = tail &+ 1

    filled.signal()

    return true
  }

  open func get() -> Int?
  {
    if closed && tail &- head <= 0 { return nil }

    _ = filled.wait(timeout: DispatchTime.distantFuture)

    if tail &- head > 0
    {
      let e = element
      head = head &+ 1

      empty.signal()
      return e
    }
    else
    {
      assert(closed, #function)
      filled.signal()
      return nil
    }
  }

  open func selectGet(_ select: ChannelSemaphore, selection: Selection)
  {
  }

  open func extract(_ selection: Selection) -> Int?
  {
    return nil
  }

  open func selectPut(_ select: ChannelSemaphore, selection: Selection)
  {
  }

  open func insert(_ selection: Selection, newElement: Int) -> Bool
  {
    return false
  }
}
