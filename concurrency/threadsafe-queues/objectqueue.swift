//
//  objectqueue.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

final public class ObjectQueue<T: AnyObject>: SequenceType, GeneratorType
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
    return idQueueRealCount(head)
  }

  public func enqueue(item: T)
  {
    idEnqueue(head, item)
    OSAtomicIncrement32Barrier(&size)
  }

  public func dequeue() -> T?
  {
    if OSAtomicDecrement32Barrier(&size) >= 0
    {
      return idDequeue(head) as? T
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
