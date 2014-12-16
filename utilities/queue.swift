//
//  queue.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  A simple queue, implemented as a linked list.
*/

public class Queue<T>: SequenceType, GeneratorType
{
  final private var head: Node<T>?
  final private var tail: Node<T>!

  final private var size: Int64

  public init()
  {
    head = nil
    tail = nil
    size = 0
  }

  public init(newElement: T)
  {
    let newNode = Node<T>(newElement)
    head = newNode
    tail = newNode
    size = 1
  }

  final public var isEmpty: Bool { return size == 0 }

  final public var count: Int { return Int(size) }

  public func realCount() -> Int
  {
    var i: Int64 = 0
    var node = head

    while let n = node
    { // Iterate along the linked nodes while counting
      node = n.next
      i++
    }

    assert(i == size, "Queue might have lost data")

    return Int(i)
  }

  public func enqueue(newElement: T)
  {
    let newNode = Node<T>(newElement)

    if OSAtomicIncrement64(&size) == 1
    {
      head = newNode
      tail = newNode
      return
    }

    tail.next = newNode
    tail = newNode
  }

  public func dequeue() -> T?
  {
    if OSAtomicDecrement64(&size) >= 0
    {
      let oldhead = head!

      // Promote the 2nd item to 1st
      head = oldhead.next

      // Logical housekeeping
      if size == 0 { tail = nil }

      return oldhead.element
    }

    // queue is empty
    OSAtomicIncrement64(&size)
    return nil
  }

  // Implementation of GeneratorType

  public func next() -> T?
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
  A simple Node for the Queue implemented above.
  Clearly an implementation detail.
*/

private class Node<T>
{
  let element: T
  var next: Node<T>? = nil

  /**
    The purpose of a new Node<T> is to become last in a Queue<T>.
  */

  init(_ e: T)
  {
    element = e
  }
}
