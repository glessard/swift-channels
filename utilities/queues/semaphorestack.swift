//
//  semaphoreosqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

final class SemaphoreStack: QueueType, SequenceType, GeneratorType
{
  private let head = AtomicStackInit()
  private let pool = AtomicStackInit()

  // MARK: init/deinit

  init() { }

  convenience init(_ newElement: dispatch_semaphore_t)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // first, empty the queue
    while UnsafePointer<COpaquePointer>(head).memory != nil
    {
      let node = UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(head, 0))
      node.destroy()
      node.dealloc(1)
    }
    // release the queue head structure
    AtomicStackRelease(head)

    // drain the pool
    while UnsafeMutablePointer<COpaquePointer>(pool).memory != nil
    {
      UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0)).dealloc(1)
    }
    // finally release the pool queue
    AtomicStackRelease(pool)
  }

  // MARK: QueueType interface

  var isEmpty: Bool {
    return UnsafePointer<COpaquePointer>(head).memory == nil
  }

  var count: Int {
    return (UnsafePointer<COpaquePointer>(head).memory == nil) ? 0 : countElements()
  }

  func countElements() -> Int
  {
    // Not thread safe.

    var i = 0
    var node = UnsafePointer<UnsafeMutablePointer<SemaphoreNode>>(head).memory
    while node != nil
    { // Iterate along the linked nodes while counting
      node = node.memory.next
      i++
    }

    return i
  }
  
  func enqueue(newElement: dispatch_semaphore_t)
  {
    var node = UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<SemaphoreNode>.alloc(1)
    }
    node.initialize(SemaphoreNode(newElement))

    OSAtomicEnqueue(head, node, 0)
  }

  func dequeue() -> dispatch_semaphore_t?
  {
    let node = UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(head, 0))

    if node != nil
    {
      let element = node.memory.elem
      node.destroy()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }
    return nil
  }

  // MARK: GeneratorType implementation

  func next() -> dispatch_semaphore_t?
  {
    return dequeue()
  }

  // MARK: SequenceType implementation

  func generate() -> Self
  {
    return self
  }
}

private struct SemaphoreNode
{
  var next: UnsafeMutablePointer<SemaphoreNode> = nil
  let elem: dispatch_semaphore_t

  init(_ e: dispatch_semaphore_t)
  {
    elem = e
  }
}
