//
//  Tokenize.swift
//
//  Created by Guillaume Lessard on 2014-08-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

func tokenize(source: [UInt8]) -> [Slice<UInt8>]
{
  var words = [Slice<UInt8>]()
  words.reserveCapacity(10_000)

  var lastIndex = 0
  let LF: UInt8 = 10
  for var i=0; i<source.count; i++
  {
    if source[i] == LF
    {
      words.append(source[lastIndex..<i])
      lastIndex = i+1
    }
  }

  return words
}

func tokenize(source: [UInt8], output: Chan<[(Slice<UInt8>)]>)
{
  var words = [(Slice<UInt8>)]()
  words.reserveCapacity(100)

  let tic = Time()
  var wordcount = 0

  func SendAndFlush()
  {
    output <- words
    wordcount += words.count
    words.removeAll(keepCapacity: true)
  }

  var lastIndex = 0
  let LF: UInt8 = 10
  for var i=0; i<source.count; i++
  {
    if source[i] == LF
    {
      words.append(source[lastIndex..<i])
      lastIndex = i+1

      if words.count == words.capacity { SendAndFlush() }
    }
  }

  if words.count > 0 { SendAndFlush() }

  syncprint("Extracted \(wordcount) words with a thread lifetime of \(tic.toc)")
  output.close()
}

func TokenizeToChannel(source: [UInt8]) -> ReadChan<[(Slice<UInt8>)]>
{
  var channel = Chan.Make(type: [Slice<UInt8>](), 1)

  async { tokenize(source, channel) }

  return ReadChan.Wrap(channel)
}
