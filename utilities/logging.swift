//
//  logging.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch
import Foundation.NSThread

private var PrintQueue: dispatch_queue_attr_t! =
                        dispatch_queue_create("com.tffenterprises.printqueue", DISPATCH_QUEUE_SERIAL)

private var PrintGroup: dispatch_group_t! = dispatch_group_create()

/**
  A wrapper for println that runs all print requests on a serial queue

  Writes a basic thread identifier (main or back), the textual representation
  of `object`, and a newline character onto the standard output.

  The textual representation is obtained from the `object` using its protocol
  conformances, in the following order of preference: `Streamable`,
  `Printable`, `DebugPrintable`.

  :param: object the item to be printed
*/

public func syncprint<T>(object: T)
{
  var message = NSThread.currentThread().isMainThread ? "[main] " : "[back] "

  assert(PrintQueue != nil && PrintGroup != nil, "Init failure in logging.swift")
  dispatch_group_async(PrintGroup, PrintQueue) { print(object, &message); println(message) }
}

/**
  Block until all tasks created by syncprint() have completed.
*/

public func syncprintwait()
{
  // Wait at most 200ms for the last messages to print out.
  let res = dispatch_group_wait(PrintGroup, dispatch_time(DISPATCH_TIME_NOW, 200_000_000))
  if res != 0
  {
    dispatch_suspend(PrintQueue)
    NSThread.sleepForTimeInterval(0.1)
    println("Giving up on waiting")
  }
}
