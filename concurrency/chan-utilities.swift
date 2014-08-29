//
//  chan-utilities.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Merge the channels in the channels array into one.
  Every item from the input channels will be able to be received via the returned channel.

  :param: channels an array of (read-only) channels to merge.

  :return: a single channel that will allow a receiver to get every message sent the input channels.
*/

func RRMerge<T>(channels: [ReadChan<T>]) -> ReadChan<T>
{
  if channels.count == 0
  { // Not likely to happen, but...
    let c = Chan<T>.Make(0)
    c.close()
    // return a closed channel.
    return ReadChan.Wrap(c)
  }

  let capacity = channels.reduce(0) { $0 + $1.capacity }
  let mergeChannel = Chan<T>.Make(capacity)

  // A non-clever, reliable, round-robin merging method.
  async {
    mergeloop: for var i=0, closed=0; true; i++
    {
      if let element = <-channels[i % channels.count]
      {
        mergeChannel <- element
        closed = 0
      }
      else
      {
        closed += 1
      }

      if closed == channels.count { break mergeloop }
      // All channels are closed. Job done.
    }

    mergeChannel.close()
  }

  return ReadChan.Wrap(mergeChannel)
}
