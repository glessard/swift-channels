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

public class ShuffledSequence<C: CollectionType where
                              C.Index: RandomAccessIndexType>: SequenceType, GeneratorType
{
  private let collection: C
  private let count: Int

  private var step = 0
  private var i: [C.Index]

  public init(_ input: C)
  {
    collection = input
    count = countElements(collection) as Int
    i = Array(collection.startIndex..<collection.endIndex)
  }

  public func next() -> C.Generator.Element?
  {
    if step < count
    {
      // select element
      let j = step + Int(arc4random_uniform(UInt32(count-step)))

      // swap element to the current step in the array
      if j != step { (i[j],i[step]) = (i[step],i[j]) }
      let index = i[step]

      // step past the selected element's index
      step += 1

      // return the new random element.
      return collection[index]
    }

    return nil
  }

  public func generate() -> Self
  {
    return self
  }
}
