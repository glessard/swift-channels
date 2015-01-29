//
//  merge-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Merge an array of Receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses the select() function to merge channels; it will only block
  if all channels block. The output channel will close when all inputs are closed.

  :param: channels an array of Receivers to merge.

  :return: a single Receiver provide access to get every message received by the input Receivers.
*/

public func merge<R: ReceiverType where R: Selectable>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  if channels.count == 0
  { // Not likely to happen, but return a closed channel.
    return Receiver(Chan<R.ReceivedElement>())
  }

  let (tx, rx) = Channel.Make(R.ReceivedElement.self, channels.count*2)

  async {
    let selectables = channels.map { $0 as Selectable }
    while let (s, selection) = select(selectables)
    {
      if let element: R.ReceivedElement = selection.getData()
      {
        tx <- element
      }
    }

    tx.close()
  }

  return rx
}
