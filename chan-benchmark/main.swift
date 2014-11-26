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

var buffered = Channel.Wrap(Buffered1Chan<Int>())

tic = Time()

for i in 0..<iterations
{
  buffered.tx <- i
  if let r = <-buffered.rx
  {
    assert(r == i)
  }
}
buffered.tx.close()

println(tic.toc)


buffered = Channel.Wrap(Buffered1Chan<Int>())

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


let unbuffered = Channel.Wrap(UnbufferedChan<Int>())

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

let buflen = iterations/1000
let bufferedA = Channel.Wrap(BufferedAChan<Int>(buflen))

tic = Time()

for j in 0..<(iterations/buflen)
{
  for i in 0..<buflen
  {
    bufferedA.tx <- i
  }

  for i in 0..<buflen
  {
    _ = <-bufferedA.rx
  }
}
bufferedA.tx.close()

println(tic.toc)

let bufferedQ = Channel.Wrap(BufferedQChan<Int>(buflen))

tic = Time()

for j in 0..<(iterations/buflen)
{
  for i in 0..<buflen
  {
    bufferedQ.tx <- i
  }

  for i in 0..<buflen
  {
    _ = <-bufferedQ.rx
  }
}
bufferedQ.tx.close()

println(tic.toc)
