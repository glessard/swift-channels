//
//  pointerqueue.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

final public class PointerQueue<T>: SequenceType, GeneratorType
{
  private let head: COpaquePointer

  private var size: Int32 = 0

  init()
  {
    head = AtomicQueueInit()
  }

  deinit
  {
    // first, empty the queue
    while size > 0
    {
      _ = dequeue()
    }

    // then release the queue head structure
    AtomicQueueRelease(head)
  }

  public var isEmpty: Bool { return size < 1 }

  public var count: Int { return Int(size) }

  public func realCount() -> Int
  {
    return ptrQueueRealCount(head)
  }

  public func enqueue(item: T)
  {
    let p = UnsafeMutablePointer<T>.alloc(1)
    p.initialize(item)
    ptrEnqueue(head, p)
    OSAtomicIncrement32Barrier(&size)
  }

  public func dequeue() -> T?
  {
    if OSAtomicDecrement32Barrier(&size) >= 0
    {
      let p = UnsafeMutablePointer<T>(ptrDequeue(head))
      let item = p.move()
      p.dealloc(1)
      return item
    }
    else
    { // We decremented once too many; increment once to correct.
      OSAtomicIncrement32Barrier(&size)
      return nil
    }
  }

  // Implementation of GeneratorType

  final public func next() -> T?
  {
    return dequeue()
  }

  // Implementation of SequenceType

  public func generate() -> Self
  {
    return self
  }
}
