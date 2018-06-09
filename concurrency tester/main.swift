//
//  main.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Changing the various wait times (in worker() and in the workElements loop)
  can illustrate the contention cases for multiple senders and multiple receivers.

  The number of starts and stops of the senders and receivers queues is minimized
  so as to avoid unnecessary out-of-order message transmissions. In the pthreads
  case, randomness could be increased by substituting all calls to pthread_cond_signal
  with calls to pthread_cond_broadcast instead.
*/

import Darwin
//import Channels

func worker(_ inputChannel: Receiver<Int>, _ outputChannel: Sender<(Int,Int,Int)>)
{
  var messageCount = 0

  // obtain values from inputChannel until it is closed.
  while let v = <-inputChannel
  {
    messageCount += 1
    Thread.Sleep(10) //+arc4random_uniform(25))
    // a "complex" calculation
    let s = (0...v).reduce(0, +)
    outputChannel <- (messageCount, v, s)
  }

  syncprint("inputChannel has been closed")
  outputChannel.close()
}

var workChan = Channel.Wrap(QUnbufferedChan<Int>())
var outChan  = Channel.Wrap(QUnbufferedChan<(Int,Int,Int)>())

let workers = 5
let workerTimeInterval = 10
for w in 1...workers
{
  async {
    Thread.Sleep(w*workerTimeInterval)
    worker(workChan.rx, outChan.tx)
  }
}

let workElements = 10
let workElementTimeInterval = 10
for a in 0..<workElements
{
  async {
    Thread.Sleep(workElementTimeInterval*(a+1))
    workChan.tx <- a
  }
}
// Uncomment the following to close the channel prematurely
//async { Time.Sleep(workElements*70); syncprint("closing work channel"); workChan.tx.close() }

var outputArray = [Int?](repeating: nil, count: workElements)

// receive data from channel until it is closed
for (i,(c,v,s)) in outChan.rx.enumerated()
{
  outputArray[v] = s
  syncprint(String(format: "%02d: (%02d) %02d %ld", i, c, v, s))

  if i >= workElements-1 { workChan.tx.close() }
}

let errors = outputArray.filter { $0 == nil }

Thread.Sleep(100)
syncprint("Dropped \(errors.count) elements")
syncprintwait()
