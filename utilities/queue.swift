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

  final private var size: Int = 0

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

  final public var count: Int { return size }

  public func realCount() -> Int
  {
    var i: Int = 0
    var node = head

    while let n = node
    { // Iterate along the linked nodes while counting
      node = n.next
      i++
    }

//    assert(i == size, "Queue might have lost data")

    return i
  }

  public func enqueue(newElement: T)
  {
    let newNode = Node<T>(newElement)

    if (size == 0)
    {
//      assert(tail == nil, "Queue has a tail but no head")

      size = 1
      head = newNode
      tail = newNode
      return
    }

    size += 1

    // tail can only be nil when head is nil.
//    assert(tail != nil, "Queue is missing its tail while not missing its head")
//    assert(tail.next == nil, "Queue tail is not the actual tail")

    tail.next = newNode
    tail = newNode
  }

  public func dequeue() -> T?
  {
    if let oldhead = head
    {
      size -= 1
      
      // Promote the 2nd item to 1st
      head = oldhead.next

      // Logical housekeeping
      if size == 0 { tail = nil }

      return oldhead.element
    }

    // queue is empty
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
