//
//  main.swift
//  chan-benchmark
//
//  Created by Guillaume Lessard on 2014-09-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Channels

let iterations = 100_000

var buffered: Chan<Int> = Chan.Make(1)

var tic = Time()

for i in 0..<iterations
{
  buffered <- i
  let a = <-buffered
}
buffered.close()

println(tic.toc)

let unbuffered = Chan<Int>.Make()

tic = Time()

async {
  for i in 0..<iterations
  {
    unbuffered <- i
  }
  unbuffered.close()
}

while let a = <-unbuffered { }

println(tic.toc)


let insane = Chan<Int>.Make(1)

tic = Time()

async {
  for i in 0..<iterations
  {
    async { insane <- i }
  }
}

for i in 0..<iterations
{
  let a = <-insane
}

insane.close()
println(tic.toc)
