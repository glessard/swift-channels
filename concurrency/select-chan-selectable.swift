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

public func Select<C: SelectableChannel>(options: C...) -> (C?, SelectionType)
{
  assert(options.count > 0, "Select requires at least one argument")

  return Select(options)
}

public func Select<C: SelectableChannel>(options: [C])  -> (C?, SelectionType)
{
  let resultChan = SelectChan<SelectionType>()

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

    let signal = option.selectRead(resultChan, messageID: option)
    signals.append(signal)
  }

  // Unblock any remaining waiting threads upon function exit.
  DeferredTaskList().defer { for signal in signals { signal() } }

  if closedOptions < options.count
  {
    if let selection = <-resultChan
    { // This should not be necessary, but some protocols are failing.
      if let selection = selection as? Selection<C.ReadElement>
      {
        return (selection.getMessageID() as? C, selection)
      }
    }
  }

  let nilS: Selectable? = nil
  return (nil, Selection(messageID: resultChan, messageData: nilS))
}
