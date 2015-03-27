//
//  main.swift
//  queue-test
//
//  Created by Guillaume Lessard on 2015-03-26.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Dispatch

let iterations = 10000
var tic: Time
var dt: Interval

let s = dispatch_semaphore_create(0)!

tic = Time()
for _ in 0..<iterations
{
  dispatch_semaphore_signal(s)
  dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
}
dt = tic.toc
println("\(dt) \(dt/iterations)")

var q = SemaphoreQueue()
q.enqueue(s)
tic = Time()
for _ in 0..<iterations
{
  if let s = q.dequeue()
  {
    dispatch_semaphore_signal(s)
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
    q.enqueue(s)
  }
}
dt = tic.toc
println("\(dt) \(dt/iterations)")

q.enqueue(s)
tic = Time()
for _ in 0..<iterations
{
  if let s = q.dequeue()
  {
    dispatch_semaphore_signal(s)
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
    q.enqueue(dispatch_semaphore_create(0))
  }
}
dt = tic.toc
println("\(dt) \(dt/iterations)")

var cq = SemaphoreChanQueue()
cq.enqueue(SemaphoreChan(s))
tic = Time()
for _ in 0..<iterations
{
  if let c = cq.dequeue(), let s = c.get()
  {
    dispatch_semaphore_signal(s)
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)
    cq.enqueue(SemaphoreChan(s))
  }
}
dt = tic.toc
println("\(dt) \(dt/iterations)")

enum FancySemaphore
{
  case s(dispatch_semaphore_t)
  case c(SemaphoreChan)
}

var fq = FastQueue<FancySemaphore>()
fq.enqueue(.s(s))
tic = Time()
for _ in 0..<iterations
{
  switch fq.dequeue()
  {
  case .None: continue
  case .Some(let fs):
    switch fs
    {
    case .s(let dsema):
      dispatch_semaphore_signal(dsema)
      dispatch_semaphore_wait(dsema, DISPATCH_TIME_FOREVER)
//      fq.enqueue(.s(dsema))
      fq.enqueue(.c(SemaphoreChan(dsema)))

    case .c(let chan):
      if let dsema = chan.get()
      {
        dispatch_semaphore_signal(dsema)
        dispatch_semaphore_wait(dsema, DISPATCH_TIME_FOREVER)
        fq.enqueue(.s(dsema))
//        fq.enqueue(.c(SemaphoreChan(dsema)))
      }
    }
  }
}
dt = tic.toc
println("\(dt) \(dt/iterations)")
