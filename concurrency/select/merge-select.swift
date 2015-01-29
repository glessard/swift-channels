//
//  merge-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Merge an array of channels into one Receiver
  Every item from the input channels will be able to be received via the returned channel.
  This function uses a simple round-robin approach to merging channels; if any one
  of the input channel blocks, the whole thing might block.

  :param: channels an array of Receivers to merge.

  :return: a single Receiver provide access to get every message received by the input Receivers.
*/

//public func merge<R: ReceiverType where R: Selectable>(channels: [R]) -> Receiver<R.ReceivedElement>
public func merge<T>(channels: [Receiver<T>]) -> Receiver<T>
{
  if channels.count == 0
  { // Not likely to happen, but return a closed channel.
    return Receiver(Chan<T>())
  }

  let (tx, rx) = Channel.Make(T.self, channels.count*2)

  async {
    while let (s, selection) = select(channels)
    {
      if let element: T = selection.getData()
      {
        tx <- element
      }
    }

    tx.close()
  }

  return rx
}
