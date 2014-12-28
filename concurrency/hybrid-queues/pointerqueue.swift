//
//  pointerqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-27.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

private let offset = PointerNodeLinkOffset()
private let length = PointerNodeSize()

final public class PointerQueue<T>: SequenceType, GeneratorType
{
  private let head = AtomicQueueInit()
  private var size: Int32 = 0

  convenience init(_ newElement: T)
  {
    self.init()
    enqueue(newElement)
  }

  deinit
  {
    // first, empty the queue
    while size > 0
    {
      dequeue()
    }

    // then release the queue head structure
    AtomicQueueRelease(head)
  }

  public var isEmpty: Bool { return size < 1 }

  public var count: Int { return Int(size) }

  public func realCount() -> Int
  {
    return AtomicQueueCountNodes(head, offset)
  }

  public func enqueue(newElement: T)
  {
    let node = UnsafeMutablePointer<PointerNode>(calloc(1, length))
    let item = UnsafeMutablePointer<T>.alloc(1)
    item.initialize(newElement)
    node.memory.item = UnsafeMutablePointer<Void>(item)

    OSAtomicFifoEnqueue(head, node, offset)
    OSAtomicIncrement32Barrier(&size)
  }

  public func dequeue() -> T?
  {
    if OSAtomicDecrement32Barrier(&size) >= 0
    {
      let node = UnsafeMutablePointer<PointerNode>(OSAtomicFifoDequeue(head, offset))
      let item = UnsafeMutablePointer<T>(node.memory.item)
      let element = item.move()
      item.dealloc(1)
      free(node)
      return element
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
