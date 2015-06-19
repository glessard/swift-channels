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

public class Timeout: ReceiverType, SelectableReceiverType
{
  private var closedState = 0
  private let closingTime: dispatch_time_t

  public init(_ time: dispatch_time_t)
  {
    closingTime = time
  }

  public convenience init(delay: Int64 = 0)
  {
    let offset = delay > 0 ? delay : 0
    self.init(dispatch_time(DISPATCH_TIME_NOW, offset))
  }

  public var isEmpty: Bool { return true }

  public var isClosed: Bool { return closedState != 0 }

  public func close()
  {
    closedState = 1
  }

  public func receive() -> Void?
  {
    if closedState == 0
    {
      let now = dispatch_time(DISPATCH_TIME_NOW, 0)
      if closingTime > now
      {
        let delay = (closingTime - now)
        var timeRequested = timespec(tv_sec: Int(delay/NSEC_PER_SEC), tv_nsec: Int(delay%NSEC_PER_SEC))
        while nanosleep(&timeRequested, &timeRequested) == -1 {}
      }
      close()
    }
    return nil
  }


  public var selectable: Bool { return closedState == 0 }

  public func selectNotify(select: ChannelSemaphore, selection: Selection)
  {
    dispatch_after(closingTime, dispatch_get_global_queue(qos_class_self(), 0)) {
      [weak self] in
      guard let this = self else { return }

      this.close()
      if select.setState(.Invalidated)
      {
        select.signal()
      }
    }
  }

  public func extract(selection: Selection) -> Void?
  {
    assertionFailure("\(__FUNCTION__) shouldn't be getting called")
    return self.receive()
  }
}
