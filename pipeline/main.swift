//
//  main.swift
//  pipeline
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

//import Foundation
import Foundation.NSData

let dicfile  = "/usr/share/dict/web2"

var data = NSData(contentsOfFile: dicfile)
var bytes = [UInt8](count: data.length, repeatedValue: 0)
data.getBytes(&bytes, length: data.length)

var wordChan = TokenizeToChannel(bytes)

let concurrentThreads = 8

//wordChan = FilterWords(wordChan)

var chans = [(ReadChan<[(Slice<UInt8>)]>)]()
for i in 0..<concurrentThreads
{
  chans.append(FilterWords(wordChan))
}

syncprint("\(chans.count) simultaneous work threads.")

var mergedWords = RRMerge(chans)

var (mCount,wCount) = (0,0)
while let w = <-mergedWords
{
  (mCount, wCount) = (mCount+1, wCount+w.count)

  // Print out a random word from the current batch.
  let slice = w[Int(arc4random_uniform(UInt32(w.count)))]
  var bytearray = Array(slice)
  bytearray.append(0)
  let ptr = UnsafePointer<CChar>(bytearray)
  syncprint(String.fromCString(ptr)!)
}

syncprint("Received \(mCount) messages containing \(wCount) words")
syncprintwait()
