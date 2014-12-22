//
//  SillyChannel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-08.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  The simplest single-element buffered channel that can
  fulfill the contract of ChannelType.
*/

public class SimpleChannel: ChannelType
{
  private var element: Int = 0
  private var elementCount = 0

  private let filled = dispatch_semaphore_create(0)!
  private let empty =  dispatch_semaphore_create(1)!

  private var closed = false

  public var isClosed: Bool { return closed }
  public var isEmpty: Bool { return elementCount <= 0 }
  public var isFull: Bool { return elementCount >= 1 }

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
    elementCount++

    dispatch_semaphore_signal(filled)

    return true
  }

  public func get() -> Int?
  {
    if closed && elementCount <= 0 { return nil }

    dispatch_semaphore_wait(filled, DISPATCH_TIME_FOREVER)

    if closed && elementCount <= 0
    {
      dispatch_semaphore_signal(filled)
      return nil
    }

    let e = element
    elementCount--

    dispatch_semaphore_signal(empty)

    return e
  }
}
