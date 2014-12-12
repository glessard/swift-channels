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


var sc = Channel.Wrap(SillyChannel())

tic = Time()

for i in 0..<iterations
{
  sc.tx <- i
  if let r = <-sc.rx
  {
    _ = r
  }
}

println(tic.toc)

var buffered = Channel.Wrap(Buffered1Chan<Int>())

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


var bufferedRaw = Buffered1Chan<Int>()

tic = Time()

for i in 0..<iterations
{
  bufferedRaw.put(i)
  if let r = bufferedRaw.get()
  {
    assert(r == i)
  }
}
bufferedRaw.close()

println(tic.toc)


bufferedRaw = Buffered1Chan<Int>()

tic = Time()

async {
  for i in 0..<iterations
  {
    bufferedRaw.put(i)
  }
  bufferedRaw.close()
}

while let a = bufferedRaw.get() { _ = a }

println(tic.toc)


//let unbuffered = Channel.Wrap(UnbufferedChan<Int>())
//
//tic = Time()
//
//async {
//  for i in 0..<iterations
//  {
//    unbuffered.tx <- i
//  }
//  unbuffered.tx.close()
//}
//
//while let a = <-unbuffered.rx { _ = a }
//
//println(tic.toc)


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

println(tic.toc)


let bufferedQRaw = BufferedQChan<Int>(buflen)

tic = Time()

for j in 0..<(iterations/buflen)
{
  for i in 0..<buflen
  {
    bufferedQRaw.put(i)
  }

  for i in 0..<buflen
  {
    _ = bufferedQRaw.get()
  }
}
bufferedQ.tx.close()

println(tic.toc)
