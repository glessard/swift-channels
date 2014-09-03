//
//  main.swift
//  queue tester
//
//  Created by Guillaume Lessard on 2014-08-20.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

println("Start")
let lim: UInt32 = 2

var q = Queue<Int>()

for i in 1...10_000
{
  let r = arc4random_uniform(lim)

  if r == 0
  {
    let a = q.realCount()
    q.enqueue(a)
    let b = q.realCount()
    assert ((b-a) == 1)
  }
  else
  {
    let a = q.realCount()
    q.dequeue()
    let b = q.realCount()
  }

  println(q.count)
}

// Drain the queue
for i in q
{
  println(i)
}

println("End")
