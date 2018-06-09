//
//  merge.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

public extension Collection where Iterator.Element: ReceiverType, Index == Int
{
  /**
    Merge an array of channel receivers into one Receiver.
    Every item from the input channels will be able to be received via the returned channel.

    This function uses a multithreaded approach to merging channels.
    The system could run out of threads if the length of the input array is too large.

    - returns: a single Receiver provide access to get every message received by the input Receivers.
  */

  public func merge() -> Receiver<Iterator.Element.ReceivedElement>
  {
    let mergeChannel = SBufferedChan<Iterator.Element.ReceivedElement>(Int(self.count)*2)
    let q = DispatchQueue.global(qos: DispatchQoS.QoSClass.current)

    q.async {
      DispatchQueue.concurrentPerform(iterations: self.count) { i in
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

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a multithreaded approach to merging channels.
  The system could run out of threads if the length of the input array is too large.

  - parameter channels: an array of Receivers to merge.
  - returns: a single Receiver provide access to get every message received by the input Receivers.
*/

public func merge<R: ReceiverType>(_ channels: [R]) -> Receiver<R.ReceivedElement>
{
  return channels.merge()
}

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a multithreaded approach to merging channels.
  The system could run out of threads if the length of the input array is too large.

  - parameter channels: a list of Receivers to merge.
  - returns: a single Receiver provide access to get every message received by the input Receivers.
*/

public func merge<R: ReceiverType>(_ channels: R...) -> Receiver<R.ReceivedElement>
{
  return channels.merge()
}

public extension Collection where Iterator.Element: ReceiverType, Index == Int
{
  /**
    Merge an array of channel receivers into one Receiver.
    Every item from the input channels will be able to be received via the returned channel.

    This function uses a simple round-robin approach to merging channels; if any one
    of the input channel blocks, the whole thing might block.

    This being said, the number of threads used is small. If the incoming data is a flood
    through unbuffered channels, this is probably the better bet. Otherwise use merge()

    - returns: a single Receiver provide access to get every message received by the input Receivers.
  */

  public func mergeRR() -> Receiver<Iterator.Element.ReceivedElement>
  {
    let mergeChannel = SBufferedChan<Iterator.Element.ReceivedElement>.Make(self.count*2)

    DispatchQueue.global(qos: DispatchQoS.QoSClass.current).async {
      // A non-clever, imperative-style round-robin merge.
      let count = self.count
      var (i, last) = (0, 0)
      while i-last < count
      {
        if let element = self[i % count].receive()
        {
          mergeChannel.put(element)
          last = i
        }
        i += 1
      }
      mergeChannel.close()
    }
    
    return Receiver(mergeChannel)
  }
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

public func mergeRR<R: ReceiverType>(_ channels: [R]) -> Receiver<R.ReceivedElement>
{
  return channels.mergeRR()
}

/**
  Merge an array of channel receivers into one Receiver.
  Every item from the input channels will be able to be received via the returned channel.

  This function uses a simple round-robin approach to merging channels; if any one
  of the input channel blocks, the whole thing might block.

  This being said, the number of threads used is small. If the incoming data is a flood
  through unbuffered channels, this is probably the better bet. Otherwise use merge()

  - parameter channels: a list of Receivers to merge.
  - returns: a single Receiver provide access to get every message received by the input Receivers.
*/

public func mergeRR<R: ReceiverType>(_ channels: R...) -> Receiver<R.ReceivedElement>
{
  return channels.mergeRR()
}
