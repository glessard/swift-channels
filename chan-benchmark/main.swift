//
//  main.swift
//  chan-benchmark
//
//  Created by Guillaume Lessard on 2014-09-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
//import Channels

let iterations = 100_000
var tic: Time

var buffered = Channel<Int>.Make(1)

tic = Time()

for i in 0..<iterations
{
  buffered.tx <- i
  if let r = <-buffered.rx
  {
    assert(r == i)
  }
}
//buffered.tx.close()

println(tic.toc)

tic = Time()

async {
  for i in 0..<iterations
  {
    buffered.tx <- i
  }
  buffered.tx.close()
}

while let a = <-buffered.rx { _ = a }

println(tic.toc)


let unbuffered = Channel<Int>.Make()

tic = Time()

async {
  for i in 0..<iterations
  {
    unbuffered.tx <- i
  }
  unbuffered.tx.close()
}

while let a = <-unbuffered.rx { _ = a }

println(tic.toc)

let buflen = iterations/100
let bufferedN = Channel<Int>.Make(buflen)

tic = Time()

for j in 0..<(iterations/buflen)
{
  for i in 0..<buflen
  {
    bufferedN.tx <- i
  }

  for i in 0..<buflen
  {
    _ = <-bufferedN.rx
  }
}
bufferedN.tx.close()

println(tic.toc)
