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
var tic: Time

var buffered: Chan<Int> = Chan.Make(1)

tic = Time()

for i in 0..<iterations
{
  buffered <- i
  _ = <-buffered
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

while let a = <-unbuffered { _ = a }

println(tic.toc)

let buflen = iterations/100
let bufferedN = Chan<Int>.Make(buflen)

tic = Time()

for j in 0..<(iterations/buflen)
{
  for i in 0..<buflen
  {
    bufferedN <- i
  }

  for i in 0..<buflen
  {
    _ = <-bufferedN
  }
}
bufferedN.close()

println(tic.toc)
