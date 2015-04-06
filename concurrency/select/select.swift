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
  let semaphoreChan = SemaphoreChan(semaphore)

  for option in shuffle(selectables)
  {
    option.selectNotify(semaphoreChan, selection: Selection(id: option))
    if semaphoreChan.isEmpty { break }
  }

  semaphore.wait()
  // We have a result
  let selection: Selection
  switch semaphore.status
  {
  case .Select(let newSelection):
    selection = newSelection

  default:
    selection = Selection(id: voidReceiver)
  }

  semaphore.setStatus(.Invalidated)
  SemaphorePool.Return(semaphore)

  return selection
}

private let voidReceiver = Receiver<()>()
