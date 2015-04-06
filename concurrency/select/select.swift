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
  let semaphore = dispatch_semaphore_create(0)!
  let semaphoreChan = SemaphoreChan(semaphore)

  for option in shuffle(selectables)
  {
    option.selectNotify(semaphoreChan, selection: Selection(id: option))
    if semaphoreChan.isEmpty { break }
  }

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
    selection = Selection(id: voidReceiver)
  }

//  dispatch_set_context(semaphore, nil)
//  SemaphorePool.enqueue(semaphore)

  return selection
}

private let voidReceiver = Receiver<()>()
