//
//  select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

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

  let semaphore = SemaphorePool.Obtain()
  semaphore.setState(.WaitSelect)

  for option in shuffle(selectables)
  {
    option.selectNotify(semaphore, selection: Selection(id: option))
    if semaphore.state != .WaitSelect { break }
  }

  if let def = withDefault where semaphore.setState(.Invalidated)
  {
    SemaphorePool.Return(semaphore)
    return Selection(id: def)
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
