//
//  async.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Utility shortcuts for Grand Central Dispatch queues

  Example:
  async { println("In the background") }

  That is simply a shortcut for
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) { println("In the background") }

  Much more economical.
*/

struct DispatchQueue
{
  static var Global: dispatch_queue_attr_t
    { return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) }

  static var Main: dispatch_queue_attr_t
    { return dispatch_get_main_queue() }
}

/**
  Execute a closure on a concurrent background thread.

  :param: coroutine the closure to execute
*/
public func async (coroutine: () -> ())
{
  dispatch_async(DispatchQueue.Global) { coroutine() }
}

/**
  Execute a closure on a concurrent background thread, discarding any return value.

  :param: coroutine the closure to execute
*/
public func async<Discarded> (coroutine: () -> Discarded)
{
  dispatch_async(DispatchQueue.Global) { _ = coroutine() }
}

/**
  Execute a closure on a concurrent background thread, and associate it with 'group'

  :param: group     the dispatch group, as obtained from dispatch_group_create()
  :param: coroutine the closure to execute
*/
public func async(#group: dispatch_group_t, coroutine: () -> ())
{
  dispatch_group_async(group, DispatchQueue.Global) { coroutine() }
}

/**
  Execute a closure on a concurrent background thread, and associate it with 'group'

  :param: group     the dispatch group, as obtained from dispatch_group_create()
  :param: coroutine the closure to execute
*/
public func async<Discarded>(#group: dispatch_group_t, coroutine: () -> Discarded)
{
  dispatch_group_async(group, DispatchQueue.Global) { _ = coroutine() }
}
