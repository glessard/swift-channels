//
//  SillyChannel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-08.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Swift

final class SillyChannel: ChannelType
{
  typealias ElementType = Int

  var element: Int? = nil

  private var elementsWritten: Int64 = 0
  private var elementsRead: Int64    = 0

  private var closed = false

  var isClosed: Bool { return closed }

  var isEmpty: Bool { return elementsWritten <= elementsRead }

  var isFull: Bool { return elementsWritten > elementsRead }

  func close()
  {
    closed = true
  }

  final func put(newElement: Int)
  {
    if (elementsWritten <= elementsRead)
    {
      element = newElement
      OSAtomicIncrement64Barrier(&elementsWritten)
    }
  }

  final func take() -> Int?
  {
    if (elementsWritten > elementsRead)
    {
      OSAtomicIncrement64Barrier(&elementsRead)
      return element
    }
    else if closed
    {
      element = nil
    }
    return nil
  }
}