//
//  SillyChannel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-08.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Swift

struct SillyChannel: ChannelType
{
  typealias Element = Int

  var element: Int = 0

  private var elementsWritten: Int64 = 0
  private var elementsRead: Int64    = 0

  private var closed = false

  var isClosed: Bool { return closed }

  var isEmpty: Bool { return elementsWritten <= elementsRead }

  var isFull: Bool { return elementsWritten > elementsRead }

  mutating func close()
  {
    closed = true
  }

  mutating func put(newElement: Int)
  {
    if (elementsWritten <= elementsRead)
    {
      element = newElement
      elementsWritten++
    }
  }

  mutating func get() -> Int?
  {
    if (elementsWritten > elementsRead)
    {
      elementsRead++
      return element
    }

    return nil
  }
}