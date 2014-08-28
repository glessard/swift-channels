//
//  Timing.swift
//
//  Created by Guillaume Lessard on 2014-06-24.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Foundation.NSDate
import Foundation.NSThread

/**
  A struct whose purpose is to pretty-print short durations of time.
*/

struct Milliseconds: Printable
{
  var milliseconds: Double = 0.0

  var description: String
  {
    if milliseconds > 5000
    { // over 5 seconds: just show seconds down to thousandths
      return (round(milliseconds)/1000).description + " s"
    }
    // otherwise round to microseconds
    return (round(1000*milliseconds)/1000).description + " ms"
  }

  init(interval: Double)
  {
    milliseconds = abs(interval)
  }

  // NSTimeInterval is nominally in seconds
  init(_ nsTimeInterval: NSTimeInterval)
  {
    self.init(interval: Double(1000*nsTimeInterval))
  }

  init(interval: Int)
  {
    self.init(interval: Double(interval))
  }
}

/**
  Timing-related wrappers for NSDate and NSThread, named for readability.
*/

class Time: Printable
{
  var d: NSDate

  init() { d = NSDate() }

  class func Now() -> Time { return Time() }

  var description: String { return d.description }
}

/**
  Additions to Time to work with Milliseconds, defined above.
*/

extension Time
{
  /**
    Readability: Time.Since() returns a Millisecond struct.
    example:
    let starttime = Time()
    println(Time.Since(starttime))
  */

  class func Since(a: NSDate) -> Milliseconds
  {
    return Milliseconds(a.timeIntervalSinceNow)
  }

  class func Since(tic: Time) -> Milliseconds
  {
    return tic.toc
  }

  /**
    An analog to the MATLAB tic ... toc time measurement function pair.
    example:
    let tic = Time()
    println(tic.toc)
  */

  var toc: Milliseconds { return Milliseconds(d.timeIntervalSinceNow) }
}

/**
  Sleep the current thread for a number of milliseconds.
*/

extension Time
{
  class func Wait(interval: Milliseconds)
  {
    Time.Wait(interval.milliseconds)
  }

  class func Wait(milliseconds: Int)
  {
    Time.Wait(Double(milliseconds))
  }

  class func Wait(milliseconds: UInt32)
  {
    Time.Wait(Double(milliseconds))
  }

  class func Wait(milliseconds: Double)
  {
    if milliseconds > 0
    { NSThread.sleepForTimeInterval(milliseconds*0.001) }
  }
}
