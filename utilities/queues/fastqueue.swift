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
  private var head: COpaquePointer = nil
  private var tail: COpaquePointer  = nil

  private let pool = AtomicStackInit()
  private var lock = OS_SPINLOCK_INIT

  init() { }

  convenience init(_ newElement: T)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // empty the queue
    var h = UnsafeMutablePointer<LinkNode>(head)
    while h != nil
    {
      let node = h
      h = node.memory.next
      UnsafeMutablePointer<T>(node.memory.elem).destroy()
      UnsafeMutablePointer<T>(node.memory.elem).dealloc(1)
      node.dealloc(1)
    }

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

  var isEmpty: Bool { return head == nil }

  var count: Int {
    return (head == nil) ? 0 : countElements()
  }

  func countElements() -> Int
  {
    // Not thread safe.

    var i = 0
    var node = UnsafeMutablePointer<LinkNode>(head)
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

    OSSpinLockLock(&lock)

    if head == nil
    {
      head = COpaquePointer(node)
      tail = COpaquePointer(node)
      OSSpinLockUnlock(&lock)
      return
    }

    UnsafeMutablePointer<LinkNode>(tail).memory.next = node
    tail = COpaquePointer(node)
    OSSpinLockUnlock(&lock)
  }

  func dequeue() -> T?
  {
    OSSpinLockLock(&lock)

    if head != nil
    {
      let node = UnsafeMutablePointer<LinkNode>(head)

      // Promote the 2nd item to 1st
      head = COpaquePointer(node.memory.next)

      // Logical housekeeping
      if head == nil { tail = nil }

      OSSpinLockUnlock(&lock)

      let element = UnsafeMutablePointer<T>(node.memory.elem).move()
      OSAtomicEnqueue(pool, node, 0)
      return element
    }

    // queue is empty
    OSSpinLockUnlock(&lock)
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
