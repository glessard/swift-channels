//
//  filter.swift
//  pipeline
//
//  Created by Guillaume Lessard on 2014-08-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

//func FilterWords<CI: ReadableChannel, CO: WritableChannel
//                 where CI.ReadElement == Array<Slice<UInt8>>, CO.WrittenElement == CI.ReadElement>
//                (input: CI, output: CO)
func FilterWords(input: ReadChan<Array<Slice<UInt8>>>, output: Chan<Array<Slice<UInt8>>>)
{
  var words = [(Slice<UInt8>)]()

  let tic = Time()
  var wordcount = 0

  let offset: UInt8 = 97
  let masterCounts = Array<Int>(count: 26, repeatedValue: 0)

  while let slices = <-input
  {
    for slice in slices
    {
      // A relatively inefficient way to find words that contain no repeated letters.
      var counts = masterCounts
      for c in slice
      {
        if (c >= offset) && (c-offset < 26)
        {
          counts[c-offset] += 1
        }

        let counted = reduce(counts, 0, +)
        if counted == slice.count
        {
          let multiples = map(counts) { $0 > 1 }
          let ungood = find(multiples, true)
          if ungood == nil
          {
            words.append(slice)
          }
        }
      }
    }

    if words.count > 0
    {
      output <- words
      wordcount += words.count
      words.removeAll(keepCapacity: true)
    }
  }

  syncprint("Found \(wordcount) words with a thread lifetime of \(tic.toc)")
  output.close()
}

//func FilterWords<CI: ReadableChannel where CI.ReadElement == Array<Slice<UInt8>>>
//                (source: CI) -> ReadChan<Array<Slice<UInt8>>>
func FilterWords(source: ReadChan<Array<Slice<UInt8>>>) -> ReadChan<Array<Slice<UInt8>>>
{
  var channel = Chan.Make(type: Array<Slice<UInt8>>(), source.capacity)

  async { FilterWords(source, channel) }

  return ReadChan.Wrap(channel)
}
