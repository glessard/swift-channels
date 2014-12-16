//
//  main.swift
//  chan-benchmark
//
//  Created by Guillaume Lessard on 2014-09-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

let iterations = 120_000
var tic: Time

var rsc = SillyChannel()
var wsc = Channel.Wrap(rsc)

tic = Time()

for i in 0..<iterations
{
  rsc.put(i)
  if let r = rsc.get()
  {
    _ = r
  }
}

syncprint(tic.toc)

var buffered = Channel.Wrap(QBuffered1Chan<Int>())

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

syncprint(tic.toc)
//syncprint(results.reduce(0, combine: +)/Double(iterations))


buffered = Channel.Wrap(QBuffered1Chan<Int>())

tic = Time()

async {
  for i in 0..<iterations
  {
    buffered.tx <- i
  }
  buffered.tx.close()
}

while let a = <-buffered.rx { _ = a }

syncprint(tic.toc)


buffered = Channel.Wrap(Buffered1Chan<Int>())

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

syncprint(tic.toc)


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

syncprint(tic.toc)


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

syncprint(tic.toc)


let buflen = iterations/1000

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

syncprint(tic.toc)

syncprintwait()
