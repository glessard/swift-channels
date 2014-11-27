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
  public typealias Element = C.Generator.Element
  public typealias Index = C.Index

  private let collection: C
  private var indexShuffler: IndexShuffler<Range<Index>>

  public init(_ input: C)
  {
    collection = input
    indexShuffler = IndexShuffler(collection.startIndex..<collection.endIndex)
  }

  public mutating func next() -> Element?
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
  public typealias Index = S.Generator.Element

  private let count: Int
  private var step = -1
  private var i: [Index]

  public init(_ input: S)
  {
    i = Array(input)
    count = countElements(i) as Int
  }

  public mutating func next() -> Index?
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

  public func generate() -> IndexShuffler
  {
    return self
  }
}
