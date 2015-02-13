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
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { println("In the background") }

  Much more economical.
*/

struct DispatchQueue
{
  static var Global: dispatch_queue_attr_t {
    return dispatch_get_global_queue(qos_class_self(), 0)
  }

  static var Main: dispatch_queue_attr_t {
    return dispatch_get_main_queue()
  }
}

/**
  Execute a closure on a concurrent background thread.

  :param: task the closure to execute
*/
public func async (task: () -> ())
{
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) { task() }
}

/**
  Execute a closure on a concurrent background thread, discarding any return value.

  :param: task the closure to execute
*/
public func async<IgnoredType> (task: () -> IgnoredType)
{
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) { _ = task() }
}

/**
  Execute a closure on a concurrent background thread, and associate it with 'group'

  :param: group     the dispatch group, as obtained from dispatch_group_create()
  :param: task the closure to execute
*/
public func async(#group: dispatch_group_t, task: () -> ())
{
  dispatch_group_async(group, dispatch_get_global_queue(qos_class_self(), 0)) { task() }
}

/**
  Execute a closure on a concurrent background thread, and associate it with 'group'

  :param: group     the dispatch group, as obtained from dispatch_group_create()
  :param: task the closure to execute
*/
public func async<IgnoredType>(#group: dispatch_group_t, task: () -> IgnoredType)
{
  dispatch_group_async(group, dispatch_get_global_queue(qos_class_self(), 0)) { _ = task() }
}
