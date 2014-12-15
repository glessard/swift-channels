//
//  anythingqueue.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

final public class AnythingQueue<T>: SequenceType, GeneratorType
{
  private let q = ObjectQueue<Box<T>>()

  public var isEmpty: Bool { return q.isEmpty }

  public var count: Int { return q.count }

  public func realCount() -> Int
  {
    return q.realCount()
  }

  public func enqueue(item: T)
  {
    q.enqueue(Box(item))
  }

  public func dequeue() -> T?
  {
    return q.dequeue()?.element
  }

  // Implementation of GeneratorType

  final public func next() -> T?
  {
    return dequeue()
  }

  // Implementation of SequenceType

  public func generate() -> Self
  {
    return self
  }
}


/**
  A simple Box for the Queue implemented above.
  Clearly an implementation detail.
*/

private class Box<T>
{
  let element: T

  init(_ e: T)
  {
    element = e
  }
}
