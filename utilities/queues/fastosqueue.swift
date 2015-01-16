//
//  fastosqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

final class FastOSQueue<T>: QueueType, SequenceType, GeneratorType
{
  private let head = AtomicQueueInit()
  private let pool = AtomicStackInit()

  init() { }

  convenience init(_ newElement: T)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // empty the queue
    while UnsafeMutablePointer<COpaquePointer>(head).memory != nil
    {
      let node = UnsafeMutablePointer<LinkNode>(OSAtomicFifoDequeue(head, 0))
      UnsafeMutablePointer<T>(node.memory.elem).destroy()
      UnsafeMutablePointer<T>(node.memory.elem).dealloc(1)
      node.dealloc(1)
    }
    // release the queue head structure
    AtomicQueueRelease(head)

    // drain the pool
    while UnsafeMutablePointer<COpaquePointer>(pool).memory != nil
    {
      let node = UnsafeMutablePointer<LinkNode>(OSAtomicDequeue(pool, 0))
      UnsafeMutablePointer<T>(node.memory.elem).dealloc(1)
      node.dealloc(1)
    }
    // release the pool stack structure
    AtomicStackRelease(pool)
  }

  var isEmpty: Bool {
    return UnsafeMutablePointer<COpaquePointer>(head).memory == nil
  }

  var count: Int {
    return (UnsafeMutablePointer<COpaquePointer>(head).memory == nil) ? 0 : countElements()
  }

  func countElements() -> Int
  {
    // Not thread safe.

    var i = 0
    var node = UnsafeMutablePointer<UnsafeMutablePointer<LinkNode>>(head).memory
    while node != nil
    { // Iterate along the linked nodes while counting
      node = node.memory.next
      i++
    }

    return i
  }

  func enqueue(newElement: T)
  {
    var node = UnsafeMutablePointer<LinkNode>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<LinkNode>.alloc(1)
      node.memory.elem = COpaquePointer(UnsafeMutablePointer<T>.alloc(1))
    }
    node.memory.next = nil
    UnsafeMutablePointer<T>(node.memory.elem).initialize(newElement)

    OSAtomicFifoEnqueue(head, node, 0)
  }

  func dequeue() -> T?
  {
    let node = UnsafeMutablePointer<LinkNode>(OSAtomicFifoDequeue(head, 0))
    if node != nil
    {
      let element = UnsafeMutablePointer<T>(node.memory.elem).move()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }

    return nil
  }

  func next() -> T?
  {
    return dequeue()
  }

  func generate() -> Self
  {
    return self
  }
}
