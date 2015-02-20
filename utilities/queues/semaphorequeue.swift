//
//  semaphorequeue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin
import Dispatch

final class SemaphoreQueue: QueueType, SequenceType, GeneratorType
{
  private var head: UnsafeMutablePointer<SemaphoreNode> = nil
  private var tail: UnsafeMutablePointer<SemaphoreNode> = nil

  private let pool = AtomicStackInit()
  private var lock = OS_SPINLOCK_INIT

  init() { }

  convenience init(_ newElement: dispatch_semaphore_t)
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
      node.destroy()
      node.dealloc(1)
    }

    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      UnsafeMutablePointer<SemaphoreNode>(OSAtomicDequeue(pool, 0)).dealloc(1)
    }
    AtomicStackRelease(pool)
  }

  var isEmpty: Bool { return head == nil }

  var count: Int {
    return (head == nil) ? 0 : countElements()
  }

  func countElements() -> Int
  {
    // Not thread safe.

    var i = 0
    var node = UnsafeMutablePointer<SemaphoreNode>(head)
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

    OSSpinLockLock(&lock)
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
    OSSpinLockUnlock(&lock)
  }

  func dequeue() -> dispatch_semaphore_t?
  {
    OSSpinLockLock(&lock)
    let node = head
    if node != nil
    { // Promote the 2nd item to 1st
      head = node.memory.next
    }
    OSSpinLockUnlock(&lock)

    if node != nil
    {
      let element = node.memory.elem
      node.destroy()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }
    return nil
  }

  // Implementation of GeneratorType

  func next() -> dispatch_semaphore_t?
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
  let elem: dispatch_semaphore_t

  init(_ e: dispatch_semaphore_t)
  {
    elem = e
  }
}
