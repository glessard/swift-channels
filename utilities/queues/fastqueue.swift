//
//  fastqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

final class FastQueue<T>: QueueType, SequenceType, GeneratorType
{
  private var head: UnsafeMutablePointer<Node> = nil
  private var tail: UnsafeMutablePointer<Node> = nil

  private let pool = AtomicStackInit()

  // MARK: init/deinit

  init() { }

  convenience init(_ newElement: T)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // empty the queue
    while head != nil
    {
      let node = head
      head = node.memory.next
      let elem = node.memory.elem() as UnsafeMutablePointer<T>
      elem.destroy()
      elem.dealloc(1)
      node.dealloc(1)
    }

    // drain the pool
    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      let node = UnsafeMutablePointer<Node>(OSAtomicDequeue(pool, 0))
      let elem = node.memory.elem() as UnsafeMutablePointer<T>
      elem.dealloc(1)
      node.dealloc(1)
    }
    // release the pool stack structure
    AtomicStackRelease(pool)
  }

  // MARK: QueueType interface

  var isEmpty: Bool { return head == nil }

  var count: Int {
    return (head == nil) ? 0 : countElements()
  }

  func countElements() -> Int
  {
    // Not thread safe.

    var i = 0
    var node = head
    while node != nil
    { // Iterate along the linked nodes while counting
      node = node.memory.next
      i++
    }

    return i
  }

  func enqueue(newElement: T)
  {
    var node = UnsafeMutablePointer<Node>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<Node>.alloc(1)
      node.memory = Node(UnsafeMutablePointer<T>.alloc(1))
    }
    node.memory.next = nil
    node.memory.elem().initialize(newElement)

    if head == nil
    {
      head = node
      tail = node
    }
    else
    {
      tail.memory.next = node
      tail = node
    }
  }

  func dequeue() -> T?
  {
    let node = head
    if node != nil
    { // Promote the 2nd item to 1st
      head = node.memory.next

      let element: T = node.memory.elem().move()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }
    return nil
  }

  // MARK: GeneratorType implementation

  func next() -> T?
  {
    return dequeue()
  }

  // MARK: SequenceType implementation

  func generate() -> Self
  {
    return self
  }
}

private struct Node
{
  var next: UnsafeMutablePointer<Node> = nil
  var p: COpaquePointer

  init<T>(_ p: UnsafeMutablePointer<T>)
  {
    self.p = COpaquePointer(p)
  }

  func elem<T>() -> UnsafeMutablePointer<T>
  {
    return UnsafeMutablePointer<T>(p)
  }
}
