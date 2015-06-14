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

class Timer: ReceiverType
{
  private var closedState: Int32 = 0
  private let closingTime: dispatch_time_t

  private let barrier = dispatch_group_create()!

  init(_ time: dispatch_time_t)
  {
    closingTime = time

    dispatch_group_enter(barrier)
  }

  convenience init(delay timeOffset: Int64 = 0)
  {
    let offset = timeOffset > 0 ? timeOffset : 0
    self.init(dispatch_time(DISPATCH_TIME_NOW, offset))
  }

  var isEmpty: Bool  { return true }

  var isClosed: Bool { return closedState != 0 }

  func close()
  {
    if closedState == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &closedState)
    { // Only one thread can get here
      dispatch_group_leave(barrier)
    }
  }

  func receive() -> Void?
  {
    if closedState == 0
    {
      dispatch_group_wait(barrier, closingTime)
      close()
    }
    return nil
  }
}
