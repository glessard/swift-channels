//
//  ShuffleTests.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-26.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Cocoa
import XCTest

class ShuffleTests: XCTestCase
{
  let a = Array(stride(from: -5.0, to: 1e4, by: 0.8))

  func testPerformanceShuffle()
  {
    self.measureBlock() {
      var s = Array(shuffle(self.a))
    }
  }

  func testPerformanceShuffledSequence()
  {
    self.measureBlock() {
      var s = Array(ShuffledSequence(self.a))
    }
  }

  func testPerformanceSequenceOfShuffledSequence()
  {
    self.measureBlock() {
      var s = Array(SequenceOf(ShuffledSequence(self.a)))
    }
  }

  func testPerformancePermutationGenerator()
  {
    self.measureBlock() {
      let shuffledIndices = IndexShuffler(self.a.startIndex..<self.a.endIndex)
      let permutation = PermutationGenerator(elements: self.a, indices: shuffledIndices)
      var s = Array(permutation)
    }
  }

  func testPerformancePermutationGeneratorOfSequenceOfShuffledIndices()
  {
    self.measureBlock() {
      let shuffledIndices = IndexShuffler(self.a.startIndex..<self.a.endIndex)
      let permutation = PermutationGenerator(elements: self.a, indices: SequenceOf(shuffledIndices))
      var s = Array(permutation)
    }
  }

  func testPerformanceSequenceOfPermutationGenerator()
  {
    self.measureBlock() {
      let shuffledIndices = IndexShuffler(self.a.startIndex..<self.a.endIndex)
      let permutation = PermutationGenerator(elements: self.a, indices: shuffledIndices)
      var s = Array(SequenceOf(permutation))
    }
  }
}
