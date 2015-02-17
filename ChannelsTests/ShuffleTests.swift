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

  func testPerformanceControl()
  {
    self.measureBlock() {
      let s = Array(SequenceOf(self.a))
      //      let s = Array(PermutationGenerator(elements: self.a, indices: SequenceOf(indices(self.a))))
    }
  }

  func testPerformanceShuffle()
  {
    self.measureBlock() {
      let s = Array(shuffle(self.a))
    }
  }

  func testPerformanceShuffledSequence()
  {
    self.measureBlock() {
      let s = Array(ShuffledSequence(self.a))
    }
  }

  func testPerformanceSequenceOfShuffledSequence()
  {
    self.measureBlock() {
//      let s = Array(SequenceOf(ShuffledSequence(self.a)))
      let soss = SequenceOf(ShuffledSequence(self.a))
      let s = Array(soss)
    }
  }

  func testPerformancePermutationGenerator()
  {
    self.measureBlock() {
      let s = Array(PermutationGenerator(elements: self.a, indices: IndexShuffler(indices(self.a))))
    }
  }

  func testPerformancePermutationGeneratorOfSequenceOfShuffledIndices()
  {
    self.measureBlock() {
      let shuffledIndices = IndexShuffler(indices(self.a))
//      let permutation = PermutationGenerator(elements: self.a, indices: SequenceOf(shuffledIndices))
      let s = Array(PermutationGenerator(elements: self.a, indices: SequenceOf(shuffledIndices)))
    }
  }

  func testPerformanceSequenceOfPermutationGenerator()
  {
    self.measureBlock() {
//      let permutation = PermutationGenerator(elements: self.a, indices: IndexShuffler(indices(self.a)))
      let shuffledIndices = IndexShuffler(indices(self.a))
      let permutation = PermutationGenerator(elements: self.a, indices: shuffledIndices)
      let s = Array(SequenceOf(permutation))
    }
  }
}
