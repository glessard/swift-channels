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
  private var head: COpaquePointer = nil
  private var tail: COpaquePointer = nil

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
    var h = UnsafeMutablePointer<SemaphoreNode>(head)
    while h != nil
    {
      let node = h
      h = node.memory.next
      node.destroy()
      node.dealloc(1)
    }

    while UnsafeMutablePointer<COpaquePointer>(pool).memory != nil
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
      head = COpaquePointer(node)
      tail = COpaquePointer(node)
      OSSpinLockUnlock(&lock)
      return
    }

    UnsafeMutablePointer<SemaphoreNode>(tail).memory.next = node
    tail = COpaquePointer(node)
    OSSpinLockUnlock(&lock)
  }

  func dequeue() -> dispatch_semaphore_t?
  {
    OSSpinLockLock(&lock)

    if head != nil
    {
      let node = UnsafeMutablePointer<SemaphoreNode>(head)

      // Promote the 2nd item to 1st
      head = COpaquePointer(node.memory.next)

      // Logical housekeeping
      if head == nil { tail = nil }

      OSSpinLockUnlock(&lock)

      let element = node.memory.elem
      node.destroy()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }

    // queue is empty
    OSSpinLockUnlock(&lock)
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
