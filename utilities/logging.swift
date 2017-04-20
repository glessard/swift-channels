//
//  syncprint.swift
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//
//  https://gist.github.com/glessard/826241431dcea3655d1e
//

import Dispatch
import Foundation.NSThread

private let PrintQueue = DispatchQueue(label: "com.tffenterprises.syncprint", attributes: [])
private let PrintGroup = DispatchGroup()

private var silenceOutput: Int32 = 0

/**
  A wrapper for println that runs all requests on a serial queue

  Writes a basic thread identifier (main or back), the textual representation
  of `object`, and a newline character onto the standard output.

  The textual representation is obtained from the `object` using its protocol
  conformances, in the following order of preference: `Streamable`,
  `Printable`, `DebugPrintable`.

  :param: object the item to be printed
*/

public func syncprint<T>(_ object: T)
{
  let message = Foundation.Thread.current.isMainThread ? "[main] " : "[back] "

  PrintQueue.async(group: PrintGroup) {
    // There is no particularly straightforward way to ensure an atomic read
    if OSAtomicAdd32(0, &silenceOutput) == 0
    {
      print(message, object)
    }
  }
}

/**
  Block until all tasks created by syncprint() have completed.
*/

public func syncprintwait()
{
  // Wait at most 200ms for the last messages to print out.
  let res = PrintGroup.wait(timeout: DispatchTime.now() + Double(200_000_000) / Double(NSEC_PER_SEC))
  if res == .timedOut
  {
    OSAtomicIncrement32Barrier(&silenceOutput)
    PrintGroup.notify(queue: PrintQueue) {
      print("Skipped output")
      OSAtomicDecrement32Barrier(&silenceOutput)
    }
  }
}
