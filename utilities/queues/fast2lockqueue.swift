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

final public class Fast2LockQueue<T>: QueueType, SequenceType, GeneratorType
{
  private var head: UnsafeMutablePointer<Node<T>> = nil
  private var tail: UnsafeMutablePointer<Node<T>> = nil

  private var hlock = OS_SPINLOCK_INIT
  private var tlock = OS_SPINLOCK_INIT

  private let pool = AtomicStackInit()

  // MARK: init/deinit

  public init()
  {
    head = UnsafeMutablePointer<Node<T>>.alloc(1)
    head.memory = Node(UnsafeMutablePointer<T>.alloc(1))
    tail = head
  }

  public convenience init(_ newElement: T)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // empty the queue
    let emptyhead = head
    head = head.memory.next
    emptyhead.memory.elem.dealloc(1)
    emptyhead.dealloc(1)

    while head != nil
    {
      let node = head
      head = node.memory.next
      node.memory.elem.destroy()
      node.memory.elem.dealloc(1)
      node.dealloc(1)
    }

    // drain the pool
    while UnsafePointer<COpaquePointer>(pool).memory != nil
    {
      let node = UnsafeMutablePointer<Node<T>>(OSAtomicDequeue(pool, 0))
      node.memory.elem.dealloc(1)
      node.dealloc(1)
    }
    // release the pool stack structure
    AtomicStackRelease(pool)
  }

  public var count: Int {
    return (head == tail) ? 0 : countElements()
  }

  public func countElements() -> Int
  {
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

  public var isEmpty: Bool { return head == tail }

  public func enqueue(newElement: T)
  {
    var node = UnsafeMutablePointer<Node<T>>(OSAtomicDequeue(pool, 0))
    if node == nil
    {
      node = UnsafeMutablePointer<Node<T>>.alloc(1)
      node.memory = Node(UnsafeMutablePointer<T>.alloc(1))
    }
    node.memory.next = nil
    node.memory.elem.initialize(newElement)

    OSSpinLockLock(&tlock)
    // hopefully tail.memory.next is stored atomically
    // this is the one possible collision between dequeue() and enqueue()
    tail.memory.next = node
    tail = node
    OSSpinLockUnlock(&tlock)
  }

  public func dequeue() -> T?
  {
    OSSpinLockLock(&hlock)
    // hopefully head.memory.next is read atomically.
    // this is the one possible collision between dequeue() and enqueue()
    let next = head.memory.next
    if next != nil
    {
      let oldhead = head
      head = next
      let element = next.memory.elem.move()
      OSSpinLockUnlock(&hlock)

      OSAtomicEnqueue(pool, oldhead, 0)
      return element
    }
    OSSpinLockUnlock(&hlock)
    return nil
  }

  // MARK: GeneratorType implementation

  public func next() -> T?
  {
    return dequeue()
  }

  // MARK: SequenceType implementation

  public func generate() -> Self
  {
    return self
  }
}

private struct Node<T>
{
  var nptr: UnsafeMutablePointer<Void> = nil
  let elem: UnsafeMutablePointer<T>

  init(_ p: UnsafeMutablePointer<T>)
  {
    elem = p
  }

  var next: UnsafeMutablePointer<Node<T>> {
    get { return UnsafeMutablePointer(nptr) }
    set { nptr = UnsafeMutablePointer(newValue) }
  }
}
