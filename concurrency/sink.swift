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

public class Sink<T>: SenderType, SelectableSenderType
{
  public var isFull: Bool { return false }
  public var isClosed: Bool { return false }

  public func close() {}

  public func send(newElement: T) -> Bool
  {
    return true
  }

  public var selectable: Bool { return true }

  public func selectNotify(select: ChannelSemaphore, selection: Selection)
  {
    if select.setState(.Invalidated)
    {
      select.signal()
    }
  }

  public func insert(selection: Selection, newElement: T) -> Bool
  {
    return true
  }
}
