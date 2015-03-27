//
//  semaphorequeue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

enum SuperSemaphore
{
  case semaphore(dispatch_semaphore_t)
  case selection(SemaphoreChan, Selectable)
}

final class SuperSemaphoreQueue: QueueType, SequenceType, GeneratorType
{
  private var head: UnsafeMutablePointer<SemaphoreNode> = nil
  private var tail: UnsafeMutablePointer<SemaphoreNode> = nil

  private let pool = AtomicStackInit()

  // MARK: init/deinit

  init() { }

  convenience init(_ newElement: SuperSemaphore)
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
      switch node.memory.elem
      {
      case .semaphore(let s):
        dispatch_semaphore_signal(s)
      case .selection(let c, _):
        if let s = c.get() { dispatch_semaphore_signal(s) }
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

  // MARK: QueueType interface

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

  func enqueue(newElement: dispatch_semaphore_t)
  {
    enqueue(.semaphore(newElement))
  }

  func enqueue(newElement: SemaphoreChan, id: Selectable)
  {
    enqueue(.selection(newElement, id))
  }

  func enqueue(newElement: SuperSemaphore)
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

  func undequeue(newElement: SuperSemaphore)
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
  
  func dequeue() -> SuperSemaphore?
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

  // MARK: GeneratorType implementation

  func next() -> SuperSemaphore?
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
  let elem: SuperSemaphore

  init(_ s: SuperSemaphore)
  {
    elem = s
  }
}
