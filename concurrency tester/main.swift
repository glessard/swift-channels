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
func worker<CI: ReadableChannel, CO: WritableChannel
  where CI.ReadElement == Int, CO.WrittenElement == ReturnTuple>
  (inputChannel: CI, outputChannel: CO)
  //func worker(inputChannel: ReadChan<Int>, outputChannel: WriteChan<(Int,Int,Int)>)
{
  var messageCount = 0

  // obtain values from inputChannel until it is closed.
  while let v = <-inputChannel
  {
    messageCount += 1
    Time.Wait(10) //+arc4random_uniform(25))
    // a "complex" calculation
    let s = reduce(0...v, 0, +)
    outputChannel <- (messageCount, v, s)
  }

  syncprint("inputChannel has been closed")
  outputChannel.close()
}

var workChan = Chan<Int>.Make(1)
var outChan  = Chan.Make(type: (0,0,0), 0)

async { Time.Wait(10); worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }
async { Time.Wait(20); worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }
async { Time.Wait(30); worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }
async { Time.Wait(40); worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }
async { Time.Wait(50); worker(ReadChan.Wrap(workChan), WriteChan.Wrap(outChan)) }

let workElements = 10;
for a in 0..<workElements
{
  async { Time.Wait(100+1000*a); workChan <- a }
}
// Uncomment the following to close the channel prematurely
//async { Time.Wait(workElements*20); syncprint("closing work channel"); workChan.close() }

var outputArray = [Int?](count: workElements, repeatedValue: nil)

// receive data from channel until it is closed
for (i,(c,v,s)) in enumerate(outChan)
{
  outputArray[v] = s
  syncprint(String(format: "%02d: (%02d) %02d %ld", i, c, v, s))

  if i >= workElements-1 { workChan.close() }
}

let errors = outputArray.filter { $0 == nil }

syncprint("Dropped \(errors.count) elements")
syncprintwait()
