//
//  future.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-14.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

/**
  Execute a closure on a concurrent backround thread,
  with the ability to retrieve its result at a later time.

  The returned closure will allow retrieval of the original closure's result.
  If the result is ready, the call will return immediately.
  If the result is not ready yet, the call will block until the result can be returned.

  The result can be used multiple times; the original closure is executed only once.

  :param: task the closure to execute asynchronously.

  :return: a new closure with the same return type, to retrieve the result of 'task'
*/

public func future<T>(task: () -> T) -> () -> T
{
  let group = dispatch_group_create()
  let queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)

  var result: T! = nil
  dispatch_group_async(group, queue) { result = task() }

  return {
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
    return result
  }
}

private func test()
{
  let deferredResult0: () -> Double = future { return 0.0 }

  let task = { () -> Int in
    sleep(1)
    return 10
  }
  let deferredResult1 = future(task)

  let deferredResult2 = future { () -> Double in
    sleep(2)
    return 20.0
  }

  println("Waiting for deferred results")
  println("Deferred result 0 is \(deferredResult0())")
  println("Deferred result 1 is \(deferredResult1())")
  println("Deferred result 2 is \(deferredResult2())")
  println("Deferred result 1 is \(deferredResult1())")
}
