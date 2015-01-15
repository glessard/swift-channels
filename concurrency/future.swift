//
//  future.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-14.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

public func future<T>(task: () -> T) -> Receiver<T>
{
  let (tx, rx) = Channel<T>.MakeSingleton()

  async {
    tx <- task()
  }

  return rx
}

private func test()
{
  let task = { () -> Int in
    sleep(1)
    return 10
  }
  let deferredResult1 = future(task)

  let deferredResult2 = future { () -> Double in
    sleep(2)
    return 20.0
  }

  println("Result of work while waiting for deferred results")
  println("Deferred result 1 is \(<-deferredResult1)")
  println("Deferred result 2 is \(<-deferredResult2)")
}
