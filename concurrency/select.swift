//
//  chan-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Select registers to be notified by the first of a list of Selectable items.
  It
*/

public func Select(options: Selectable...) -> (Selectable, Selectee?)
{
  assert(options.count > 0, "Select requires at least one argument")

  let resultChan = SelectChan<Selectable>()

  // This should have worked.
  // Optional protocols-as-types have strange behaviour in beta6
  //  for option in enumerate(shuffle(options))
  //  {
  //    option.selectRead(resultChan, message: option)
  //  }

  // The visitation order is randomized, because otherwise
  // the first Selectable in the list would be unfairly favored.

  let shuffled = ShuffledSequence(options)
  var closedOptions = 0
  for i in 0..<options.count
  {
    // Optional protocols-as-types have strange behaviour in beta6
    var opt = shuffled.next()
    if let option = opt
    {
      if option.invalidSelection
      {
        closedOptions += 1
        continue
      }

      option.selectRead(resultChan, message: option)
    }
  }

  if closedOptions < options.count
  {
    if let message = resultChan.read()
    {
      return (message, resultChan.stash)
    }
  }

  resultChan.close()
  return (resultChan, nil)
}
