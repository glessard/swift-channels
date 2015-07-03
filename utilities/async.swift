//
//  async.swift
//  swiftiandispatch
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  Utility shortcuts for Grand Central Dispatch
  Example:
  async { println("In the background") }

  That is simply a shortcut for
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) { println("In the background") }

  Much more economical, much less noisy.

  A queue or a qos_class_t can be provided as a parameter in addition to the closure.
  When none is supplied, the global queue at the current qos class will be used.
  In all cases, a dispatch_group_t may be associated with the block to be executed.
*/

// MARK: Asynchronous tasks (straight dispatch_async and dispatch_group_async shortcuts)

public func async(task: () -> ())
{
  dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), task)
}

public func async(group group: dispatch_group_t, task: () -> ())
{
  dispatch_group_async(group, dispatch_get_global_queue(qos_class_self(), 0), task)
}

public func async(qos: qos_class_t, task: () -> ())
{
  dispatch_async(dispatch_get_global_queue(qos, 0), task)
}

public func async(qos: qos_class_t, group: dispatch_group_t, task: () -> ())
{
  dispatch_group_async(group, dispatch_get_global_queue(qos, 0), task)
}

public func async(queue: dispatch_queue_t, task: () -> ())
{
  dispatch_async(queue, task)
}

public func async(queue: dispatch_queue_t, group: dispatch_group_t, task: () -> ())
{
  dispatch_group_async(group, queue, task)
}

/**
  An asynchronous computation result.

  The get() method will return the result, blocking until it is ready.
  If the result is ready when get() is called, it will return immediately.
*/

public struct Result<T>
{
  internal let group: dispatch_group_t
  internal let result: () -> T

  public var value: T { return result() }
}

// MARK: Asynchronous tasks with return values.

public func async<T>(task: () -> T) -> Result<T>
{
  return async(dispatch_get_global_queue(qos_class_self(), 0), task: task)
}

public func async<T>(group group: dispatch_group_t, task: () -> T) -> Result<T>
{
  return async(dispatch_get_global_queue(qos_class_self(), 0), group: group, task: task)
}

public func async<T>(qos: qos_class_t, task: () -> T) -> Result<T>
{
  return async(dispatch_get_global_queue(qos, 0), task: task)
}

public func async<T>(qos: qos_class_t, group: dispatch_group_t, task: () -> T) -> Result<T>
{
  return async(dispatch_get_global_queue(qos, 0), group: group, task: task)
}

public func async<T>(queue: dispatch_queue_t, task: () -> T) -> Result<T>
{
  let g = dispatch_group_create()!
  var result: T! = nil

  dispatch_group_enter(g)
  dispatch_async(queue) {
    result = task()
    dispatch_group_leave(g)
  }

  return Result(group: g) {
    () -> T in
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
    return result
  }
}

public func async<T>(queue: dispatch_queue_t, group: dispatch_group_t, task: () -> T) -> Result<T>
{
  let g = dispatch_group_create()!
  var result: T! = nil

  dispatch_group_enter(g)
  dispatch_group_async(group, queue) {
    result = task()
    dispatch_group_leave(g)
  }

  return Result(group: g) {
    () -> T in
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
    return result
  }
}

// MARK: Asynchronous tasks with input parameters and no return values.

extension Result
{
  public func notify(task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify(group group: dispatch_group_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), group: group, task: task)
  }

  public func notify(qos: qos_class_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify(qos: qos_class_t, group: dispatch_group_t, task: (T) -> ())
  {
    return notify(dispatch_get_global_queue(qos, 0), group: group, task: task)
  }

  public func notify(queue: dispatch_queue_t, task: (T) -> ())
  {
    dispatch_group_notify(self.group, queue) {
      task(self.result())
    }
  }

  public func notify(queue: dispatch_queue_t, group: dispatch_group_t, task: (T) -> ())
  {
    dispatch_group_enter(group)
    dispatch_group_notify(self.group, queue) {
      task(self.result())
      dispatch_group_leave(group)
    }
  }
}

// MARK: Asynchronous tasks with input parameters and return values

extension Result
{
  public func notify<U>(task: (T) -> U) -> Result<U>
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), task: task)
  }

  public func notify<U>(group group: dispatch_group_t, task: (T) -> U) -> Result<U>
  {
    return notify(dispatch_get_global_queue(qos_class_self(), 0), group: group, task: task)
  }

  public func notify<U>(qos: qos_class_t, task: (T) -> U) -> Result<U>
  {
    return notify(dispatch_get_global_queue(qos, 0), task: task)
  }

  public func notify<U>(qos: qos_class_t, group: dispatch_group_t, task: (T) -> U) -> Result<U>
  {
    return notify(dispatch_get_global_queue(qos, 0), group: group, task: task)
  }

  public func notify<U>(queue: dispatch_queue_t, task: (T) -> U) -> Result<U>
  {
    let g = dispatch_group_create()!
    var result: U! = nil

    dispatch_group_enter(g)
    dispatch_group_notify(self.group, queue) {
      result = task(self.result())
      dispatch_group_leave(g)
    }

    return Result<U>(group: g) {
      () -> U in
      dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
      return result
    }
  }

  public func notify<U>(queue: dispatch_queue_t, group: dispatch_group_t, task: (T) -> U) -> Result<U>
  {
    let g = dispatch_group_create()!
    var result: U! = nil

    dispatch_group_enter(group)
    dispatch_group_enter(g)
    dispatch_group_notify(self.group, queue) {
      result = task(self.result())
      dispatch_group_leave(g)
      dispatch_group_leave(group)
    }

    return Result<U>(group: g) {
      () -> U in
      dispatch_group_wait(g, DISPATCH_TIME_FOREVER)
      return result
    }
  }
}
