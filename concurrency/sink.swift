//
//  sink.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-19.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

/**
  A `SenderType` equivalent of `/dev/null`.
  Works for any type, will never block.
  Might not be useful either.
*/

open class Sink<T>: SenderType, SelectableSenderType
{
  open var isFull: Bool { return false }
  open var isClosed: Bool { return false }

  open func close() {}

  open func send(_ newElement: T) -> Bool
  {
    return true
  }

  open var selectable: Bool { return true }

  open func selectNotify(_ select: ChannelSemaphore, selection: Selection)
  {
    if select.setState(.select)
    {
      select.selection = selection
      select.signal()
    }
  }

  open func insert(_ selection: Selection, newElement: T) -> Bool
  {
    return true
  }
}
