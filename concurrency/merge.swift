//
//  merge.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a multithreaded approach to merging channels.
  The system could run out of threads if the length of the input array is too large.

  - parameter channels: an array of Receivers to merge.
  - returns: a single Receiver provide access to get every message received by the input Receivers.
*/

public extension CollectionType where Self.Generator.Element: ReceiverType, Self.Index == Int
{
  public func merge() -> Receiver<Generator.Element.ReceivedElement>
  {
    let mergeChannel = SChan<Generator.Element.ReceivedElement>.Make(self.count*2)
    let q = dispatch_get_global_queue(qos_class_self(), 0)

    dispatch_async(q) {
      dispatch_apply(self.count, q) { i in
        let chan = self[i]
        while let element = chan.receive()
        {
          mergeChannel.put(element)
        }
      }
      mergeChannel.close()
    }
    
    return Receiver(mergeChannel)
  }
}

public func merge<R: ReceiverType>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  return channels.merge()
}

public func merge<R: ReceiverType>(channels: R...) -> Receiver<R.ReceivedElement>
{
  return channels.merge()
}

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a simple round-robin approach to merging channels; if any one
  of the input channel blocks, the whole thing might block.

  This being said, the number of threads used is small. If the incoming data is a flood
  through unbuffered channels, this is probably the better bet. Otherwise use merge()

  - parameter channels: an array of Receivers to merge.
  - returns: a single Receiver provide access to get every message received by the input Receivers.
*/

public extension CollectionType where Self.Generator.Element: ReceiverType, Self.Index == Int
{
  public func mergeRR() -> Receiver<Generator.Element.ReceivedElement>
  {
    if self.count == 0
    { // Return a Receiver for a closed channel in this case
      return Receiver()
    }

    let mergeChannel = SChan<Generator.Element.ReceivedElement>.Make(self.count*2)

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      // A non-clever, imperative-style round-robin merge.
      let count = self.count
      for var i=0, last=0; true; i++
      {
        if let element = self[i % count].receive()
        {
          mergeChannel.put(element)
          last = i
        }
        else
        {
          if (i-last >= count)
          { // All channels are closed. Job done.
            break
          }
        }
      }
      mergeChannel.close()
    }
    
    return Receiver(mergeChannel)
  }
}

public func mergeRR<R: ReceiverType>(channels: [R]) -> Receiver<R.ReceivedElement>
{
  return channels.mergeRR()
}

public func mergeRR<R: ReceiverType>(channels: R...) -> Receiver<R.ReceivedElement>
{
  return channels.mergeRR()
}
