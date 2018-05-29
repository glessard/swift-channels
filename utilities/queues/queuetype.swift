//
//  queuetype.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-30.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

// MARK: QueueType

public protocol QueueType: Sequence, IteratorProtocol, ExpressibleByArrayLiteral
{
  associatedtype Element

  /**
   Initialize an empty queue
   */

  init()

  /**
   Initialize a queue with an initial element

   - parameter newElement: the initial element of the new queue
   */

  init(_ newElement: Element)

  /**
   Return whether the queue is empty
   For some implementations, it might be faster to check for queue emptiness
   rather than attempting a dequeue on an empty queue. For those cases,
   this would be the fast check.
   */

  var isEmpty: Bool { get }

  /**
   Add a new element to the queue.

   - parameter newElement: a new element
   */

  func enqueue(_ newElement: Element)

  /**
   Return the oldest element from the queue, or nil if the queue is empty.

   :return: an element, or nil
   */

  func dequeue() -> Element?

  /**
   Return the number of elements currently in the queue.
   This is not at all likely to be thread-safe.
   */

  var count: Int { get }
}

/**
 Implementation of GeneratorType based on QueueType
 */

// MARK: GeneratorType for QueueType

public extension QueueType
{
  public func next() -> Element?
  {
    return dequeue()
  }
}

/**
 Convenience initializers
 */

// MARK: Convenience Initializers

public extension QueueType
{
  /**
   Initialize a queue with an initial element

   - parameter newElement: the initial element of the new queue
   */

  public init(_ newElement: Element)
  {
    self.init()
    self.enqueue(newElement)
  }

  /**
   Initialize a queue from an array

   - parameter elements: a collection of initial elements
   */

  public init<C: Collection>(collection: C) where C.Iterator.Element == Element
  {
    self.init()
    for element in collection
    {
      self.enqueue(element)
    }
  }

  /**
   Initialize a queue with initial elements
   (implements ArrayLiteralConvertible)

   - parameter arrayLiteral: the initial elements of the new queue
   */

  public init(arrayLiteral elements: Element...)
  {
    self.init(collection: elements)
  }
}
