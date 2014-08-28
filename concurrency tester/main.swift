//
//  main.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

// Workaround for (presumably) a generics parser bug:
typealias ReturnTuple = (Int,Int,Int)
//func worker<CI: ReadableChannel, CO: WritableChannel
//            where CI.ReadElement == Int, CO.WrittenElement == ReturnTuple>
//           (inputChannel: CI, outputChannel: CO)
func worker(inputChannel: ReadChan<Int>, outputChannel: WriteChan<(Int,Int,Int)>)
{
  var messageCount = 0

  // obtain values from inputChannel until it is closed.
  while let v = <-inputChannel
  {
    messageCount += 1
    Time.Wait(25+arc4random_uniform(25))
    // a "complex" calculation
    let s = reduce(0..<v, 0, +)
    outputChannel <- (messageCount, v, s)
  }

  syncprint("inputChannel has been closed")
  outputChannel.close()
}

var workChan = Chan<Int>.Make()
var outChan  = Chan.Make(type: (0,0,0))

async { worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }

let workElements = 40;
for a in 0..<workElements
{
  async { workChan <- a }
}
// Uncomment the following to close the channel prematurely
//async { Time.Wait(workElements*20); syncprint("closing work channel"); workChan.close() }

var outputArray = [Int?](count: workElements, repeatedValue: nil)

// receive data from channel until it is closed
for (c,v,s) in outChan
{
  outputArray[v] = s
  syncprint(String(format: "%02d: %02d %ld", c, v, s))

  if c >= workElements { workChan.close() }
}

let errors = outputArray.filter { $0 == nil }

syncprint("Dropped \(errors.count) elements")
syncprintwait()
