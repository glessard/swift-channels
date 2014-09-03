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

public func Select(options: Selectable...) -> (Selectable, Selectee)
{
  assert(options.count > 0, "Select requires at least one argument")

  let resultChan = SelectChan<Selectable>()

  // This should have worked.
  // Optional protocols-as-types have strange behaviour in beta6
  //  for option in enumerate(shuffle(options))
  //  {
  //    option.selectRead(resultChan, message: option)
  //  }

  var closedOptions = 0
  var signals = [Signal]()

  // The visitation order is randomized, because otherwise
  // the first Selectable in the list would be unfairly favored.
  // (imagine the case of multiple non-empty channels.)
  let shuffled = ShuffledSequence(options)
  for i in 0..<options.count
  {
    // Optional protocols-as-types have strange behaviour in beta6
    // The Generator approach fails in a mysterious fashion.
    var opt = shuffled.next()
    if let option = opt
    {
      if option.invalidSelection
      {
        closedOptions += 1
        continue
      }

      let signal = option.selectRead(resultChan, message: option)
      signals.append(signal)
    }
  }

  // Unblock any remaining waiting threads upon function exit.
  DeferredTaskList().defer { for signal in signals { signal() } }

  if closedOptions < options.count
  {
    if let message = resultChan.read()
    {
      return (message, resultChan.stash)
    }
  }

  let nilS: Selectable? = nil
  resultChan.close()
  return (resultChan, SelectPayload(payload: nilS))
}
