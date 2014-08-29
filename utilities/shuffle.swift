//
//  shuffle.swift
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  Get a sequence/generator wrapper of an array that returns its elements in a random order.
  The array is not modified in any way.
*/

public func shuffle<T>(a: Array<T>) -> ShuffledSequence<T>
{
  return ShuffledSequence(a)
}

/**
  A stepwise implementation of the Knuth Shuffle (a.k.a. Fisher-Yates Shuffle).
  The array is not modified: the shuffling itself is done using an adjunct array of indices.
*/

public class ShuffledSequence<T>: SequenceType, GeneratorType
{
  private let a: Array<T>

  private var step = 0
  private var i: [Int]

  public init(_ input: Array<T>)
  {
    let r = 0..<input.count
    a = input // input[r]
    i = Array(r)
  }

  public func next() -> T?
  {
    if step < a.count
    {
      if a.count == 1
      {
        step += 1
        return a[0]
      }

      // selection
      let j = step + Int(arc4random_uniform(UInt32(a.count-step)))
      let index = i[j]

      // housekeeping
      if j != step { (i[j],i[step]) = (i[step],i[j]) }
      step += 1

//      syncprint("shuffling index \(index) of \(a.count) on step \(step)")

      // result
      return a[index]
    }

    return nil
  }

  public func generate() -> Self
  {
    return self
  }
}
