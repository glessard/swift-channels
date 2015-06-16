//
//  chan-timer.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-06-13.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A timer class implemented as a channel.

  The timer takes either a dispatch_time_t or a positive time offset in nanoseconds, and the channel will close after that amount of time has passed.
  In the meantime, the channel has no capacity, therefore any attempt receive from it will block.
*/

public class Timer: ReceiverType
{
  private var closedState: Int32 = 0
  private let closingTime: dispatch_time_t

  private let barrier = dispatch_group_create()!

  public init(_ time: dispatch_time_t)
  {
    closingTime = time
    dispatch_group_enter(barrier)
  }

  public convenience init(delay timeOffset: Int64 = 0)
  {
    let offset = timeOffset > 0 ? timeOffset : 0
    self.init(dispatch_time(DISPATCH_TIME_NOW, offset))
  }

  deinit
  {
    if closedState == 0
    {
      dispatch_group_leave(barrier)
    }
  }

  public var isClosed: Bool { return closedState != 0 }

  public func close()
  {
    if closedState == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &closedState)
    { // Only one thread can get here
      dispatch_group_leave(barrier)
    }
  }

  public func receive() -> Void?
  {
    if closedState == 0
    { // given our usage, dispatch_group_wait will allocate a semaphore port regardless of the timeout value.
      // in order to occasionally save some microseconds, compare with the current time first.
      if closingTime > dispatch_time(DISPATCH_TIME_NOW, 0)
      {
        dispatch_group_wait(barrier, closingTime)
      }
      close()
    }
    return nil
  }
}
