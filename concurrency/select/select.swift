//
//  select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Select gets notified of events by the first of a list of Selectable items.
*/

public func select(options: Selectable...) -> Selection?
{
  return select(options)
}

public func select(options: [Selectable], withDefault: Selectable? = nil) -> Selection?
{
  let selectables = options.filter { $0.selectable }

  if selectables.count < 1
  { // Nothing left to do
    return nil
  }

  // The synchronous path
  for option in shuffle(selectables)
  {
    if let selection = option.selectNow(Selection(id: option))
    {
      return selection
    }
  }

  if let d = withDefault
  {
    return Selection(id: d)
  }

  // The asynchronous path
  let semaphore = SemaphorePool.Obtain()
  semaphore.setState(.WaitSelect)

  for option in shuffle(selectables)
  {
    option.selectNotify(semaphore, selection: Selection(id: option))
    if semaphore.state != .WaitSelect { break }
  }

  semaphore.wait()
  // We have a result
  let selection: Selection
  switch semaphore.state
  {
  case .Select:
    selection = semaphore.selection ?? voidSelection
    semaphore.selection = nil
    semaphore.setState(.Done)

  case .DoubleSelect:
    // this is specific to the extract() side of a double select.
    selection = semaphore.selection ?? voidSelection

  case .Invalidated, .Done:
    selection = voidSelection

  case let status: // default
    preconditionFailure("Unexpected ChannelSemaphore state (\(status)) in __FUNCTION__")
  }

  SemaphorePool.Return(semaphore)

  return selection
}

private let voidReceiver = Receiver<()>()
private let voidSelection = Selection(id: voidReceiver)
