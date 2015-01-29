//
//  select-receiver.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Select gets notified of events by the first of a list of Selectable items.
*/

public func select<T>(options: Receiver<T>...) -> (Selectable, Selection)?
{
  return select(options)
}

public func select<T>(options: [Receiver<T>]) -> (Selectable, Selection)?
{
  if options.count > 0
  {
    let semaphore = SemaphorePool.dequeue()
    let resultChan = SingletonChan(semaphore)

    var signals = [Signal]()

    for option in shuffle(options)
    {
      if option.selectable
      {
        let signal = option.selectNotify(resultChan, selectionID: option)
        signals.append(signal)
      }
    }

    if signals.count < 1
    {
      if dispatch_get_context(semaphore) != nil
      {
        // leak memory.
        dispatch_set_context(semaphore, nil)
      }
      SemaphorePool.enqueue(semaphore)
      return nil
    }

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    // We have a result
    let context = COpaquePointer(dispatch_get_context(semaphore))
    if context != nil
    {
      let selection = Unmanaged<Selection>.fromOpaque(context).takeRetainedValue()
      if let r = selection.messageID as? Receiver<T>
      {
        for signal in signals { signal() }
        dispatch_set_context(semaphore, nil)
        SemaphorePool.enqueue(semaphore)
        return (r, selection)
      }
    }

    for signal in signals { signal() }
    dispatch_set_context(semaphore, nil)
    SemaphorePool.enqueue(semaphore)
  }

//  syncprint("nil message received?")
  let c = Receiver(Chan<()>())
  return (c, Selection(selectionID: c, selectionData: Optional<()>.None))
}
