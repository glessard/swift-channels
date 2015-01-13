//
//  linknodes.swift
//  QQ
//
//  Created by Guillaume Lessard on 2015-01-06.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin

struct LinkNode
{
  var next: UnsafeMutablePointer<LinkNode> = nil
  var elem: COpaquePointer = nil

  init(_ p: COpaquePointer)
  {
    elem = p
  }

  init<T>(_ p: UnsafeMutablePointer<T>)
  {
    elem = COpaquePointer(p)
  }
}

struct LinkNodeQueueData
{
  var head: UnsafeMutablePointer<LinkNode> = nil
  var tail: UnsafeMutablePointer<LinkNode> = nil

  var lock: Int32 = OS_SPINLOCK_INIT
}


struct ObjLinkNode
{
  var next: UnsafeMutablePointer<ObjLinkNode> = nil
  var elem: AnyObject

  init(_ e: AnyObject)
  {
    elem = e
  }
}

struct AnyLinkNode
{
  var next: UnsafeMutablePointer<AnyLinkNode> = nil
  var elem: Any

  init(_ e: Any)
  {
    elem = e
  }
}
