//
//  shuffle.swift
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  Get a sequence/generator that will return a collection's elements in a random order.
  The input collection is not modified in any way.
*/

func shuffle<C: CollectionType>(c: C) -> PermutationGenerator<C, IndexShuffler<C.Index>>
{
  return PermutationGenerator(elements: c, indices: IndexShuffler(indices(c)))
}

/**
  A stepwise implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle),
  using a sequence of indices as its input.
*/

struct IndexShuffler<I: ForwardIndexType>: SequenceType, GeneratorType
{
  private var i: [I]
  private let count: Int
  private var step = -1

  init<S: SequenceType where S.Generator.Element == I>(_ input: S)
  {
    self.init(Array(input))
  }

  init(_ input: Range<I>)
  {
    self.init(Array(input))
  }

  init(_ input: Array<I>)
  {
    i = input
    count = Swift.count(input) as Int
  }

  mutating func next() -> I?
  {
    step += 1

    if step < count
    {
      // select a random Index from the rest of the array
      let j = step + Int(arc4random_uniform(UInt32(count-step)))

      // swap that Index with the one at the current step in the array
      swap(&i[j], &i[step])

      // return the new random Index.
      return i[step]
    }

    return nil
  }

  func generate() -> IndexShuffler
  {
    return self
  }
}
