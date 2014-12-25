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

public class FastQueue<T>: SequenceType, GeneratorType
{
  final private var head = UnsafeMutablePointer<Node<T>>.null()
  final private var tail = UnsafeMutablePointer<Node<T>>.null()

  final private var size = 0

  final private var lock = OS_SPINLOCK_INIT

  public init()
  {
  }

  convenience public init(newElement: T)
  {
    self.init()

    head = UnsafeMutablePointer<Node<T>>.alloc(1)
    head.initialize(Node<T>(newElement))
    tail = head
    size = 1
  }

  deinit
  {
    while size > 0
    {
      _ = dequeue()
    }
  }

  final public var isEmpty: Bool { return size == 0 }

  final public var count: Int { return size }

  public func realCount() -> Int
  {
    // For testing; don't call this under contention.

    var i = 0
    var nptr = head
    while nptr != UnsafeMutablePointer.null()
    { // Iterate along the linked nodes while counting
      nptr = UnsafeMutablePointer<Node<T>>(nptr.memory.next)
      i++
    }
    assert(i == size, "Queue might have lost data")

    return i
  }

  public func enqueue(newElement: T)
  {
    let node = UnsafeMutablePointer<Node<T>>.alloc(1)
    node.initialize(Node(newElement))

    OSSpinLockLock(&lock)

    if size <= 0
    {
      head = node
      tail = node
      size = 1
      OSSpinLockUnlock(&lock)
      return
    }

    tail.memory.next = UnsafeMutablePointer<Void>(node)
    tail = node
    size += 1
    OSSpinLockUnlock(&lock)
  }

  public func dequeue() -> T?
  {
    OSSpinLockLock(&lock)

    if size > 0
    {
      let oldhead = head

      // Promote the 2nd item to 1st
      head = UnsafeMutablePointer<Node<T>>(head.memory.next)
      size -= 1

      // Logical housekeeping
      if size == 0 { tail = UnsafeMutablePointer.null() }

      OSSpinLockUnlock(&lock)

      let element = oldhead.memory.element

      oldhead.destroy()
      oldhead.dealloc(1)

      return element
    }

    // queue is empty
    OSSpinLockUnlock(&lock)
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

private struct Node<T>
{
  var next = UnsafeMutablePointer<Void>.null()
  let element: T

  /**
    The purpose of a new Node<T> is to become last in a Queue<T>.
  */

  init(_ e: T)
  {
    element  = e
  }
}
