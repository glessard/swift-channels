//
//  Timing.swift
//
//  Created by Guillaume Lessard on 2014-06-24.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin.Mach.mach_time
import Darwin.C.time
import Foundation.NSDate
import QuartzCore

/**
  A struct whose purpose is to pretty-print short durations of time.
*/

public struct Interval: CustomStringConvertible
{
  let ns: Int64

  init(_ nanoseconds: Int64)
  {
    ns = nanoseconds
  }

  init(_ nanoseconds: Int)
  {
    ns = Int64(nanoseconds)
  }

  init(_ nanoseconds: Double)
  {
    ns = Int64(nanoseconds)
  }

  init(seconds: TimeInterval)
  {
    ns = Int64(seconds*1e9)
  }

  public var description: String
    {
      if abs(ns) > 5_000_000_000
      { // over 5 seconds: round to milliseconds, display as seconds
        return (Double(ns/1_000_000)/1e3).description + " s"
      }
      if abs(ns) >= 1_000_000_000
      { // over 1 second: round to 10s of µs, display as milliseconds
        return (Double(ns/10_000)/1e2).description + " ms"
      }
      if abs(ns) >= 100_000
      { // round to microseconds, display as milliseconds
        return (Double(ns/1000)/1e3).description + " ms"
      }
      if abs(ns) >= 1_000
      {
        // otherwise display as microseconds
        return (Double(ns)/1e3).description + " µs"
      }
      return ns.description + " ns"
  }
  
  public var interval: TimeInterval
  {
    return Double(ns)*1e-9
  }
}

func / (dt: Interval, n: Int) -> Interval
{
  return Interval(dt.ns/Int64(n))
}

/**
  Timing-related utility based on mach_absolute_time().
  It seems correct on Mac OS X. It might not be on iOS.
*/

public struct Time: CustomStringConvertible
{
  fileprivate let t: Int64

  public init()
  {
    t = Int64(mach_absolute_time())
  }

  /**
    offset: offset in seconds between the uptime and a timestamp that can be mapped to a date
    This is not a constant, strictly speaking. Probably close enough, though.
  */

  fileprivate static var offset: TimeInterval = { CFAbsoluteTimeGetCurrent() - CACurrentMediaTime() }()

  /**
    scale: how to scale from the mach timebase to nanoseconds. See Technical Q&A QA1398
  */

  fileprivate static var scale: mach_timebase_info = {
    var info = mach_timebase_info(numer: 0, denom: 0)
    mach_timebase_info(&info)
    return info
  }()

  /**
    An analog to the MATLAB tic ... toc time measurement function pair.
    example:
    let tic = Time()
    println(tic.toc)
  */

  public var toc: Interval
  {
    return Time() - self
  }

  public var nanoseconds: Int64
  {
    return t * Int64(Time.scale.numer)/Int64(Time.scale.denom)
  }

  public var absoluteTime: TimeInterval
  {
      return Double(self.nanoseconds)*1e-9 + Time.offset
  }

  public var description: String
  {
    return Date(timeIntervalSinceReferenceDate: absoluteTime).description
  }
}

public func -(time1: Time, time2: Time) -> Interval
{
  return Interval((time1.t - time2.t) * Int64(Time.scale.numer)/Int64(Time.scale.denom))
}

extension Time
{
  /**
    Time.Since(t: Time) returns an `Interval`.
    example:
    ```
    let starttime = Time()
    print(Time.Since(starttime))
    ```
  */

  public static func Since(_ startTime: Time) -> Interval
  {
    return Time() - startTime
  }
}

/**
  Sleep the current thread for an interval of time.
*/

public struct Thread
{
  public static func Sleep(_ interval: Interval)
  {
    if interval.ns >= 0
    {
      var timeRequested = timespec(tv_sec: Int(interval.ns/1_000_000_000), tv_nsec: Int(interval.ns%1_000_000_000))
      while nanosleep(&timeRequested, &timeRequested) == -1 {}
    }
  }

  public static func Sleep(_ ms: Int)
  {
    if ms >= 0
    {
      Sleep(Double(ms)/1000)
    }
  }

  public static func Sleep(_ ms: UInt32)
  {
    Sleep(Int(ms))
  }

  public static func Sleep(_ seconds: TimeInterval)
  {
    if seconds > 0
    {
      let wholeseconds = floor(seconds)
      var timeRequested = timespec(tv_sec: Int(wholeseconds), tv_nsec: Int((seconds-wholeseconds)*1_000_000_000))
      while nanosleep(&timeRequested, &timeRequested) == -1 {}
    }
  }
}
