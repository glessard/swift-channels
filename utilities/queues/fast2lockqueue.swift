//
//  fast2lockqueue.swift
//  QQ
//

import Darwin.libkern.OSAtomic

/**
  Two-lock queue algorithm adapted from Maged M. Michael and Michael L. Scott.,
  "Simple, Fast, and Practical Non-Blocking and Blocking Concurrent Queue Algorithms",
  in Principles of Distributed Computing '96 (PODC96)
  See also: http://www.cs.rochester.edu/research/synchronization/pseudocode/queues.html
*/

final class Fast2LockQueue: QueueType
{
  private var head: UnsafeMutablePointer<Node> = nil
  private var tail: UnsafeMutablePointer<Node> = nil

  private var hlock = OS_SPINLOCK_INIT
  private var tlock = OS_SPINLOCK_INIT

  private let pool = AtomicStackInit()

  // MARK: init/deinit

  init()
  {
    head = UnsafeMutablePointer<Node>.alloc(1)
    head.initialize(Node(.Wait))
    tail = head
  }

  convenience init(_ newElement: WaitType)
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
      case .Wait: break
      case .Notify(let block): block()
      }
      node.destroy()
      node.dealloc(1)
    }

    // drain the pool
    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      let node = UnsafeMutablePointer<Node>(OSAtomicDequeue(pool, 0))
      node.destroy()
      node.dealloc(1)
    }
    // release the pool stack structure
    AtomicStackRelease(pool)
  }

  var count: Int {
    var i = 0
    var node = head.memory.next
    while node != nil
    { // Iterate along the linked nodes while counting
      node = node.memory.next
      i++
    }
    return i
  }

  // MARK: QueueType interface

  var isEmpty: Bool { return head == tail }

  func enqueue(newElement: WaitType)
  {
    var node = UnsafeMutablePointer<Node>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<Node>.alloc(1)
    }
    node.initialize(Node(newElement))

    OSSpinLockLock(&tlock)
    // hopefully tail.memory.next is stored atomically
    // this is the one possible collision between dequeue() and enqueue()
    tail.memory.next = node
    tail = node
    OSSpinLockUnlock(&tlock)
  }

  func dequeue() -> WaitType?
  {
    OSSpinLockLock(&hlock)
    // hopefully head.memory.next is read atomically.
    // this is the one possible collision between dequeue() and enqueue()
    let next = head.memory.next
    if next != nil
    {
      let oldhead = head
      head = next
      let element = next.memory.elem
      next.memory.elem = .Wait
      OSSpinLockUnlock(&hlock)

      OSAtomicEnqueue(pool, oldhead, 0)
      return element
    }
    OSSpinLockUnlock(&hlock)
    return nil
  }
}

private struct Node
{
  var next: UnsafeMutablePointer<Node> = nil
  var elem: WaitType

  init(_ w: WaitType)
  {
    elem = w
  }
}
