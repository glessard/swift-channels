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

public func select<T>(options: Receiver<T>...) -> (Receiver<T>, Selection)?
{
  return select(options)
}

public func select<T>(options: [Receiver<T>]) -> (Receiver<T>, Selection)?
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
        dispatch_set_context(semaphore, nil)
      }
      SemaphorePool.enqueue(semaphore)
      return nil
    }

//    syncprint("\(signals.count) signals")

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
  let c = Receiver(Chan<T>())
  return (c, Selection(selectionID: c, selectionData: ()))
}


//public func select(options: Selectable...) -> (Selectable, Selection)?
//{
//  if options.count < 1
//  {
//    let c = Receiver(Chan<Void>())
//    return (c, Selection(messageID: c, messageData: ()))
//  }
//
//  let semaphore = dispatch_semaphore_create(0)!
//  let resultChan = SingletonChan(semaphore)
//  Deferred { dispatch_set_context(semaphore, nil) }
//
//  // This should have worked.
//  // Optional protocols-as-types have strange behaviour in beta6
//  //  for option in enumerate(shuffle(options))
//  //  {
//  //    option.selectRead(resultChan, message: option)
//  //  }
//
//  var closedOptions = 0
//  var signals = [Signal]()
//
//  // The visitation order is randomized, because otherwise
//  // the first Selectable in the list would be unfairly favored.
//  // (imagine the case of multiple non-empty channels.)
//  var shuffled = ShuffledSequence(options)
//  for i in 0..<options.count
//  {
//    // Optional protocols-as-types have strange behaviour in beta6
//    // The Generator approach fails in a mysterious fashion.
//    var opt = shuffled.next()
//    if let option = opt
//    {
////      if !option.validSelection
////      {
////        closedOptions += 1
////        continue
////      }
//
//      let signal = option.selectNotify(resultChan, messageID: option)
//      signals.append(signal)
//    }
//  }
//
//  // Unblock any remaining waiting threads upon function exit.
//  Deferred { for signal in signals { signal() } }
//
//  if closedOptions < options.count
//  {
//    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
//    // We have a result
//    let context = COpaquePointer(dispatch_get_context(semaphore))
//    if context != nil
//    {
//      let selection = Unmanaged<Selection>.fromOpaque(context).takeRetainedValue()
//      return (selection.messageID, selection)
//    }
//  }
//
//  let c = Receiver(Chan<Void>())
//  return (c, Selection(messageID: c, messageData: ()))
//}
