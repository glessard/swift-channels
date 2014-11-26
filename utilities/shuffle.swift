//
//  shuffle.swift
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  Get a sequence/generator wrapper of collection that will return its elements in a random order.
  The input collection is not modified in any way.
*/

public func shuffle<C: CollectionType where
                    C.Index: RandomAccessIndexType>(collection: C) -> ShuffledSequence<C>
{
  return ShuffledSequence(collection)
}

/**
  A stepwise implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle).
  The input collection is not modified: the shuffling itself is done using an adjunct array of indices.
*/

public struct ShuffledSequence<C: CollectionType where
                               C.Index: RandomAccessIndexType>: SequenceType, GeneratorType
{
  private let collection: C
  private let count: Int

  private var step = -1
  private var i: [C.Index]

  public init(_ input: C)
  {
    collection = input
    count = countElements(collection) as Int
    i = Array(collection.startIndex..<collection.endIndex)
  }

  public mutating func next() -> C.Generator.Element?
  {
    step += 1

    if step < count
    {
      // select a random element from the rest of the collection
      let j = step + Int(arc4random_uniform(UInt32(count-step)))

      // swap element to the current step in the array
      swap(&i[j], &i[step])

      // return the new random element.
      return collection[i[step]]
    }

    return nil
  }

  public func generate() -> ShuffledSequence
  {
    return self
  }
}
