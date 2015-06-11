//
//  fastqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

final class FastQueue<T>: QueueType
{
  private var head: UnsafeMutablePointer<Node<T>> = nil
  private var tail: UnsafeMutablePointer<Node<T>> = nil

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
      node.destroy()
      node.dealloc(1)
    }

    // drain the pool
    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      UnsafeMutablePointer<Node<T>>(OSAtomicDequeue(pool, 0)).dealloc(1)
    }
    // release the pool stack structure
    AtomicStackRelease(pool)
  }

  // MARK: QueueType interface

  var isEmpty: Bool { return head == nil }

  var count: Int {
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
    var node = UnsafeMutablePointer<Node<T>>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<Node<T>>.alloc(1)
    }
    node.initialize(Node(newElement))

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

      let element = node.memory.elem
      node.destroy()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }
    return nil
  }
}

private struct Node<T>
{
  var nptr: UnsafeMutablePointer<Void> = nil
  let elem: T

  init(_ e: T)
  {
    elem = e
  }

  var next: UnsafeMutablePointer<Node<T>> {
    get { return UnsafeMutablePointer<Node<T>>(nptr) }
    set { nptr = UnsafeMutablePointer<Void>(newValue) }
  }
}
