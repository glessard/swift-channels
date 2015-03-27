//
//  semaphorequeue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

final class SemaphoreChanQueue: QueueType, SequenceType, GeneratorType
{
  private var head: UnsafeMutablePointer<SemaphoreNode> = nil
  private var tail: UnsafeMutablePointer<SemaphoreNode> = nil

  private let pool = AtomicStackInit()

  init() { }

  convenience init(_ newElement: SemaphoreChan)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    while head != nil
    {
      let node = head
      head = node.memory.next
      if let s = node.memory.elem.get()
      {
        dispatch_semaphore_signal(s)
      }
      node.destroy()
      node.dealloc(1)
    }

    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0)).dealloc(1)
    }
    AtomicStackRelease(pool)
  }

  var isEmpty: Bool {
    return (head == nil)
  }

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

  func enqueue(newElement: SemaphoreChan)
  {
    var node = UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<SemaphoreNode>.alloc(1)
    }
    node.initialize(SemaphoreNode(newElement))

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

  func undequeue(newElement: SemaphoreChan)
  {
    var node = UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<SemaphoreNode>.alloc(1)
    }
    node.initialize(SemaphoreNode(newElement))

    if head == nil
    {
      head = node
      tail = node
    }
    else
    {
      node.memory.next = head
      head = node
    }
  }
  
  func dequeue() -> SemaphoreChan?
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

  func remove(elemensNonGrata: SemaphoreChan) -> Bool
  {
    if head != nil
    {
      var node = head
      if node.memory.elem === elemensNonGrata
      {
        head = node.memory.next
        node.destroy()
        OSAtomicEnqueue(pool, node, 0)
        return true
      }

      var prev = node
      node = node.memory.next
      while node != nil
      {
        if node.memory.elem === elemensNonGrata
        {
          prev.memory.next = node.memory.next
          if node == tail { tail = prev }
          node.destroy()
          OSAtomicEnqueue(pool, node, 0)
          return true
        }
        prev = node
        node = node.memory.next
      }
    }
    return false
  }

  // Implementation of GeneratorType

  func next() -> SemaphoreChan?
  {
    return dequeue()
  }

  // Implementation of SequenceType

  func generate() -> Self
  {
    return self
  }
}

private struct SemaphoreNode
{
  var next: UnsafeMutablePointer<SemaphoreNode> = nil
  let elem: SemaphoreChan

  init(_ s: dispatch_semaphore_t)
  {
    elem = SemaphoreChan(s)
  }

  init(_ c: SemaphoreChan)
  {
    elem = c
  }
}
