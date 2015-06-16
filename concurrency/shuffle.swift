//
//  shuffle.swift
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//
//  https://gist.github.com/glessard/7140fe885af3eb874e11
//

import Darwin

/**
  Get a sequence/generator of this collection's elements in a random order.
  The collection is not modified.

  - returns: A `PermutationGenerator` of self's elements, shuffled.
*/

extension CollectionType
{
  func shuffle() -> PermutationGenerator<Self, IndexShuffler<Self.Index>>
  {
    return PermutationGenerator(elements: self, indices: IndexShuffler(self.indices))
  }
}


/**
  A stepwise (lazy-ish) implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle),
  using a sequence of indices for the input. Elements (indices) from
  the input sequence are returned in a random order until exhaustion.
*/

struct IndexShuffler<I: ForwardIndexType>: SequenceType, GeneratorType
{
  private let count: Int
  private var step = -1
  private var i: [I]

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
    count = input.count
  }

  mutating func next() -> I?
  {
    // current position in the array
    step += 1

    if step < count
    {
      // select a random Index from the rest of the array
      let j = step + Int(arc4random_uniform(UInt32(count-step)))

      // swap that Index with the Index present at the current step in the array
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
