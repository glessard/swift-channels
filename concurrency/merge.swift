//
//  merge.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a multithreaded approach to merging channels.
  The system could run out of threads if the length of the input array is too large.

  :param: channels an array of Receivers to merge.

  :return: a single Receiver provide access to get every message received by the input Receivers.
*/

public func merge<R: ReceiverType>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  let (tx, rx) = Channel.Make(R.ReceivedElement.self, channels.count*2)
  let g = dispatch_group_create()!

  for chan in channels
  {
    async(group: g) {
      while let element = <-chan
      {
        tx <- element
      }
    }
  }

  async {
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
    tx.close()
  }

  return rx
}


/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a simple round-robin approach to merging channels; if any one
  of the input channel blocks, the whole thing might block.
  This being said, the number of threads used is small.

  :param: channels an array of Receivers to merge.

  :return: a single Receiver provide access to get every message received by the input Receivers.
*/

public func mergeRR<R: ReceiverType>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  if channels.count == 0
  { // Return a closed channel in this case
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
