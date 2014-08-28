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

class Queue<T>: SequenceType, GeneratorType
{
  private var head: Node<T>?
  private var tail: Node<T>!

  private var size: Int = 0

  init()
  {
    head = nil
    tail = nil
    size = 0
  }

  init(newElement: T)
  {
    let newNode = Node<T>(newElement)
    head = newNode
    tail = newNode
    size = 1
  }

  var isEmpty: Bool { return head == nil }

  var count: Int { return size }

  func realCount() -> Int
  {
    var i: Int = 0
    var node = head

    while node != nil
    { // Iterate along the linked nodes while counting
      node = node!.next
      i++
    }

    assert(i == size, "Queue might have lost data")

    return i
  }

  func enqueue(newElement: T)
  {
    let newNode = Node<T>(newElement)
    size += 1

    if (head == nil)
    {
      head = newNode
      tail = newNode
      size = 1
      return
    }

    // tail can only be nil when head is nil.
    assert(tail != nil, "Queue is missing its tail while not missing its head")
    assert(tail.next == nil, "Queue tail is not the actual tail")

    tail.next = newNode
    tail = newNode
  }

  func dequeue() -> T?
  {
    if let oldhead = head
    {
      size -= 1
      
      // Promote the 2nd item to 1st
      head = oldhead.next

      // Logical housekeeping
      if head == nil { tail = nil }

      return oldhead.element
    }

    // queue is empty
    return nil
  }

  // Implementation of GeneratorType

  func next() -> T?
  {
    return dequeue()
  }

  // Implementation of SequenceType

  func generate() -> Self
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
