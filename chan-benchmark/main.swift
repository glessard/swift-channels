//
//  main.swift
//  chan-benchmark
//
//  Created by Guillaume Lessard on 2014-09-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

let iterations = 120_000

var dt: Interval
var tic: Time
var chan: (tx: Sender<Int>, rx: Receiver<Int>)


chan = Channel<Int>.Make(1)

tic = Time()

for i in 0..<iterations
{
  chan.tx <- i
  if let r = <-chan.rx
  {
    _ = r
  }
}
chan.tx.close()

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


chan = Channel.Wrap(SChan<Int>.Make(1))

tic = Time()

for i in 0..<iterations
{
  chan.tx <- i
  if let r = <-chan.rx
  {
    _ = r
  }
}
chan.tx.close()

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


chan = Channel<Int>.Make(1)

tic = Time()

async {
  for i in 0..<iterations
  {
    chan.tx <- i
  }
  chan.tx.close()
}

while let a = <-chan.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


chan = Channel.Wrap(SChan<Int>.Make(1))

tic = Time()

async {
  for i in 0..<iterations
  {
    chan.tx <- i
  }
  chan.tx.close()
}

while let a = <-chan.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


chan = Channel<Int>.Make(0)

tic = Time()

async {
  for i in 0..<iterations
  {
    chan.tx <- i
  }
  chan.tx.close()
}

while let a = <-chan.rx { _ = a }

dt = tic.toc
syncprint("\(dt)\t\t(\(dt/iterations) per message)")


syncprintwait()
