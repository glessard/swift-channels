//
//  queuenode.swift
//  QQ
//
//  Created by Guillaume Lessard on 4/19/17.
//  Copyright © 2017 Guillaume Lessard. All rights reserved.
//

protocol OSAtomicNode
{
  init(storage: UnsafeMutableRawPointer)
  var storage: UnsafeMutableRawPointer { get }
}

private let offset = MemoryLayout<UnsafeMutableRawPointer>.stride

struct QueueNode<Element>: OSAtomicNode
{
  let storage: UnsafeMutableRawPointer

  init(storage: UnsafeMutableRawPointer)
  {
    self.storage = storage
  }

  init()
  {
    let size = offset + MemoryLayout<Element>.stride
    storage = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: 16)
    storage.bindMemory(to: (UnsafeMutableRawPointer?).self, capacity: 1).pointee = nil
    (storage+offset).bindMemory(to: Element.self, capacity: 1)
  }

  init(initializedWith element: Element)
  {
    let size = offset + MemoryLayout<Element>.stride
    storage = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: 16)
    storage.bindMemory(to: (UnsafeMutableRawPointer?).self, capacity: 1).pointee = nil
    (storage+offset).bindMemory(to: Element.self, capacity: 1).initialize(to: element)
  }

  func deallocate()
  {
    let size = offset + MemoryLayout<Element>.stride
    storage.deallocate(bytes: size, alignedTo: MemoryLayout<UnsafeMutableRawPointer>.alignment)
  }

  var next: QueueNode? {
    get {
      if let s = storage.assumingMemoryBound(to: (UnsafeMutableRawPointer?).self).pointee
      {
        return QueueNode(storage: s)
      }
      return nil
    }
    nonmutating set {
      storage.assumingMemoryBound(to: (UnsafeMutableRawPointer?).self).pointee = newValue?.storage
    }
  }

  func initialize(to element: Element)
  {
    storage.assumingMemoryBound(to: (UnsafeMutableRawPointer?).self).pointee = nil
    (storage+offset).assumingMemoryBound(to: Element.self).initialize(to: element)
  }

  func deinitialize()
  {
    (storage+offset).assumingMemoryBound(to: Element.self).deinitialize()
  }

  @discardableResult
  func move() -> Element
  {
    return (storage+offset).assumingMemoryBound(to: Element.self).move()
  }
}


import func Darwin.libkern.OSAtomic.OSAtomicEnqueue
import func Darwin.libkern.OSAtomic.OSAtomicDequeue

/// A wrapper for OSAtomicQueue

struct AtomicStack<Node: OSAtomicNode>
{
  private let head: OpaquePointer

  init()
  {
    // Initialize an OSQueueHead struct, even though we don't
    // have the definition of it. See libkern/OSAtomic.h
    //
    //  typedef volatile struct {
    //    void	*opaque1;
    //    long	 opaque2;
    //  } __attribute__ ((aligned (16))) OSQueueHead;

    let size = MemoryLayout<OpaquePointer>.size
    let count = 2

    let h = UnsafeMutableRawPointer.allocate(bytes: count*size, alignedTo: 16)
    for i in 0..<count
    {
      h.storeBytes(of: nil, toByteOffset: i*size, as: Optional<OpaquePointer>.self)
    }

    head = OpaquePointer(h)
  }

  func release()
  {
    UnsafeMutableRawPointer(head).deallocate(bytes: 2*MemoryLayout<OpaquePointer>.size, alignedTo: 16)
  }

  func push(_ node: Node)
  {
    OSAtomicEnqueue(head, node.storage, 0)
  }

  func pop() -> Node?
  {
    if let bytes = OSAtomicDequeue(head, 0)
    {
      return Node(storage: bytes)
    }
    return nil
  }
}
