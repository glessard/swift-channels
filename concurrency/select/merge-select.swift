//
//  merge-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Merge an array of Receivers into one `Receiver`.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses the `select_chan()` function to merge channels; it will only block
  if all channels block. While this sounds good, it is much slower than the other merge functions.
  
  The output channel will close when all inputs are closed.

  - parameter `channels`: an array of `Receiver` to merge.
  - returns: a single `Receiver` provide access to get every message received .
*/

public func mergeSelect<R: ReceiverType>(_ channels: [R]) -> Receiver<R.ReceivedElement>
  where R: SelectableReceiverType
{
  if channels.count == 0
  { // Not likely to happen, but return a closed channel.
    return Receiver(Chan<R.ReceivedElement>())
  }

  let (tx, rx) = Channel<R.ReceivedElement>.Make(channels.count*2)

  DispatchQueue.global(qos: DispatchQoS.QoSClass.current ?? .default).async {
    let selectables = channels.map { $0 as Selectable }
    while let selection = select_chan(selectables)
    {
      if let receiver = selection.id as? R,
         let element = receiver.extract(selection)
      {
        tx <- element
      }
    }

    tx.close()
  }

  return rx
}
