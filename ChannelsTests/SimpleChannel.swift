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

public class SimpleChannel: ChannelType, SelectableChannelType
{
  private var element: Int = 0
  private var head = 0
  private var tail = 0

  private let filled = dispatch_semaphore_create(0)!
  private let empty =  dispatch_semaphore_create(1)!

  private var closed = false

  deinit
  {
    if head < tail
    {
      dispatch_semaphore_signal(empty)
    }
  }

  public var isClosed: Bool { return closed }
  public var isEmpty: Bool { return tail &- head <= 0 }
  public var isFull: Bool { return tail &- head >= 1 }

  public func close()
  {
    if closed { return }

    closed = true

    dispatch_semaphore_signal(empty)
    dispatch_semaphore_signal(filled)
  }

  public func put(newElement: Int) -> Bool
  {
    if closed { return false }

    dispatch_semaphore_wait(empty, DISPATCH_TIME_FOREVER)

    if closed
    {
      dispatch_semaphore_signal(empty)
      return false
    }

    element = newElement
    tail = tail &+ 1

    dispatch_semaphore_signal(filled)

    return true
  }

  public func get() -> Int?
  {
    if closed && tail &- head <= 0 { return nil }

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)

    if tail &- head > 0
    {
      let e = element
      head = head &+ 1

      dispatch_semaphore_signal(empty)
      return e
    }
    else
    {
      assert(closed, __FUNCTION__)
      dispatch_semaphore_signal(filled)
      return nil
    }
  }

  public func selectGet(select: ChannelSemaphore, selection: Selection)
  {
  }

  public func extract(selection: Selection) -> Int?
  {
    return nil
  }

  public func selectPut(select: ChannelSemaphore, selection: Selection)
  {
  }

  public func insert(selection: Selection, newElement: Int) -> Bool
  {
    return false
  }
}
