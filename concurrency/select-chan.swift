//
//  chan-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
Select gets notified of events by the first of a list of Selectable items.
*/

public func Select<T>(options: Chan<T>...) -> (Chan<T>?, Selectee)
{
  assert(options.count > 0, "Select requires at least one argument")

  return Select(options)
}

public func Select<T>(options: [Chan<T>])  -> (Chan<T>?, Selectee)
{
  let resultChan = SelectChan<Selectable>()

  var closedOptions = 0
  var signals = [Signal]()

  // The visitation order is randomized, because otherwise
  // the first Selectable in the list would be unfairly favored.
  // (imagine the case of multiple non-empty channels.)
  for option in shuffle(options)
  {
    if option.invalidSelection
    {
      closedOptions += 1
      continue
    }

    let signal = option.selectRead(resultChan, message: option)
    signals.append(signal)
  }

  // Unblock any remaining waiting threads upon function exit.
  DeferredTaskList().defer { for signal in signals { signal() } }

  if closedOptions < options.count
  {
    if let message = resultChan.read() as? Chan<T>
    {
      return (message, resultChan.stash)
    }
  }

  let nilS: Selectable? = nil
  return (nil, SelectPayload(payload: nilS))
}
