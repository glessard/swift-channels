//
//  chan-timer.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A timer class implemented as a `ReceiverType`.

  `Timeout` takes either a `dispatch_time_t` or a positive time offset in nanoseconds.
  The modeled channel will get closed after that amount of time has passed, but only through a receiving attempt.
  In the meantime, the channel has no capacity, therefore any attempt to receive from it will block.
  However, as soon as the channel closes receiving operations will unblock and return `nil`.
*/

open class Timeout: ReceiverType, SelectableReceiverType
{
  fileprivate var closedState = 0
  fileprivate let closingTime: DispatchTime

  public init(_ time: DispatchTime)
  {
    closingTime = time
  }

  public convenience init(delay: Int64 = 0)
  {
    let offset = delay > 0 ? delay : 0
    self.init(DispatchTime.now() + Double(offset) / Double(NSEC_PER_SEC))
  }

  open var isEmpty: Bool { return true }

  open var isClosed: Bool { return closedState != 0 }

  open func close()
  {
    closedState = 1
  }

  open func receive() -> Void?
  {
    if closedState == 0
    {
      let now = DispatchTime.now()
      if closingTime > now
      {
        let delay = closingTime.rawValue - now.rawValue
        var timeRequested = timespec(tv_sec: Int(delay/NSEC_PER_SEC), tv_nsec: Int(delay%NSEC_PER_SEC))
        while nanosleep(&timeRequested, &timeRequested) == -1 {}
      }
      close()
    }
    return nil
  }


  open var selectable: Bool { return closedState == 0 }

  open func selectNotify(_ select: ChannelSemaphore, selection: Selection)
  {
    DispatchQueue.global(qos: DispatchQoS.current().qosClass).asyncAfter(deadline: closingTime) {
      [weak self] in
      guard let this = self else { return }

      this.close()
      if select.setState(.invalidated)
      {
        select.signal()
      }
    }
  }

  open func extract(_ selection: Selection) -> Void?
  {
    assertionFailure("\(#function) shouldn't be getting called")
    return self.receive()
  }
}
