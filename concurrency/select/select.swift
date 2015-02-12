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

public func select(options: Selectable...) -> (Selectable, Selection)?
{
  return select(options)
}

public func select(options: [Selectable]) -> (Selectable, Selection)?
{
  let selectables = options.filter { $0.selectable }

  if selectables.count < 1
  { // Nothing left to do
    return nil
  }

  // The synchronous path
  for option in shuffle(selectables)
  {
    if let selection = option.selectNow(option)
    {
      return (selection.messageID, selection)
    }
  }

  // The asynchronous path
  let semaphore = SemaphorePool.dequeue()
  let resultChan = SemaphoreChan(semaphore)

  let signals = selectables.map { $0.selectNotify(resultChan, selectionID: $0) }

  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
  // We have a result
  let context = COpaquePointer(dispatch_get_context(semaphore))
  let selection: Selection
  if context != nil
  {
    selection = Unmanaged<Selection>.fromOpaque(context).takeRetainedValue()
  }
  else
  {
    selection = Selection(selectionID: Receiver(Chan<()>()), selectionData: Optional<()>.None)
  }

  for signal in signals { signal() }
  dispatch_set_context(semaphore, nil)
  SemaphorePool.enqueue(semaphore)

  return (selection.messageID, selection)
}
