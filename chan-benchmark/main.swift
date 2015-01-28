//
//  main.swift
//  chan-benchmark
//
//  Created by Guillaume Lessard on 2014-09-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

let iterations = 120_000
let buflen = iterations/1000

var dt: Interval
var tic: Time


var buffered = Channel<Int>.Make(1)

tic = Time()

for i in 0..<iterations
{
  buffered.tx <- i
  if let r = <-buffered.rx
  {
    _ = r
  }
}
buffered.tx.close()

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


buffered = Channel<Int>.Make(1)

tic = Time()

async {
  for i in 0..<iterations
  {
    buffered.tx <- i
  }
  buffered.tx.close()
}

while let a = <-buffered.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


var unbuffered = Channel.Wrap(QUnbufferedChan<Int>())

tic = Time()

async {
  for i in 0..<iterations
  {
    unbuffered.tx <- i
  }
  unbuffered.tx.close()
}

while let a = <-unbuffered.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


var bufferedN = Channel.Wrap(SBufferedChan<Int>(buflen))

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

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


bufferedN = Channel<Int>.Make(buflen)

tic = Time()

async {
  for i in 0..<iterations
  {
    bufferedN.tx <- i
  }
  bufferedN.tx.close()
}

while let a = <-bufferedN.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


syncprintwait()
