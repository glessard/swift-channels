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

public func shuffle<C: CollectionType>(c: C) -> PermutationGenerator<C, SequenceOf<C.Index>>
{
  return PermutationGenerator(elements: c, indices: SequenceOf(IndexShuffler(c.startIndex..<c.endIndex)))
}

/**
  A stepwise implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle).
  The input collection is not modified: the shuffling itself is done using an adjunct array of indices.
*/

public struct ShuffledSequence<C: CollectionType>: SequenceType, GeneratorType
{
  private let collection: C
  private var indexShuffler: IndexShuffler<Range<C.Index>>

  public init(_ input: C)
  {
    collection = input
    indexShuffler = IndexShuffler(collection.startIndex..<collection.endIndex)
  }

  public mutating func next() -> C.Generator.Element?
  {
    if let index = indexShuffler.next()
    {
      return collection[index]
    }
    return nil
  }

  public func generate() -> ShuffledSequence
  {
    return self
  }
}

/**
  A stepwise implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle),
  using a sequence of indices for the input.
*/

public struct IndexShuffler<S: SequenceType where
                            S.Generator.Element: ForwardIndexType>: SequenceType, GeneratorType
{
  private let count: Int
  private var step = -1
  private var i: [S.Generator.Element]

  public init(_ input: S)
  {
    i = Array(input)
    count = countElements(i) as Int
  }

  public mutating func next() -> S.Generator.Element?
  {
    step += 1

    if step < count
    {
      // select a random element from the rest of the collection
      let j = step + Int(arc4random_uniform(UInt32(count-step)))

      // swap element to the current step in the array
      swap(&i[j], &i[step])

      // return the new random element.
      return i[step]
    }

    return nil
  }

  public func generate() -> IndexShuffler
  {
    return self
  }
}
