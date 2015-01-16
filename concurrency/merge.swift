//
//  merge.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-26.
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

public func merge<R: ReceiverType>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  if channels.count == 0
  { // Not likely to happen, but...
    // return a closed channel.
    return Receiver(Chan<R.ReceivedElement>())
  }

  let (tx, rx) = Channel.Make(R.ReceivedElement.self, channels.count*2)

  // A non-clever, reliable, round-robin merging method.
  async {
    for var i=0, last=0; true; i++
    {
      if let element = <-channels[i % channels.count]
      {
        tx <- element
        last = i
      }
      else
      {
        if (i-last >= channels.count)
        { // All channels are closed. Job done.
          break
        }
      }
    }

    tx.close()
  }

  return rx
}

/**
  Merge an array of channels into one Receiver
  Every item from the input channels will be able to be received via the returned channel.
  This function uses a simple round-robin approach to merging channels; if any one
  of the input channel blocks, the whole thing might block.

  :param: channels an array of Chan<T> to merge.

  :return: a single Receiver provide access to get every message received by the input Receivers.
*/

public func merge<T>(channels: [Chan<T>]) -> Receiver<T>
{
  if channels.count == 0
  { // Not likely to happen, but...
    // return a closed channel.
    return Receiver(Chan<T>())
  }

  let (tx, rx) = Channel.Make(T.self, channels.count*2)

  // A non-clever, reliable, round-robin merging method.
  async {
    for var i=0, last=0; true; i++
    {
      if let element = channels[i % channels.count].get()
      {
        tx <- element
        last = i
      }
      else
      {
        if (i-last >= channels.count)
        { // All channels are closed. Job done.
          break
        }
      }
    }

    tx.close()
  }

  return rx
}
