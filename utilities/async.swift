//
//  async.swift
//

import Dispatch

/// Utility shortcut for Grand Central Dispatch
///
/// Example:
/// ```
/// async { println("In the background") }
/// ```
/// is simply a shortcut for
/// ```
/// DispatchQueue.global().async { println("In the background") }
/// ```
/// It was a bigger deal before Swift 3.0
///
/// A `DispatchQoS` can be provided as a parameter in addition to the closure.
/// When none is supplied, the global queue at the current qos class will be used.
/// In all cases, a DispatchGroup may be associated with the block to be executed.
///
/// - parameter task: a block to be executed asynchronously.

public func async(task: @escaping () -> Void)
{
  DispatchQueue.global(qos: .current).async(execute: task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter group: a `DispatchGroup` to associate to this block execution
/// - parameter task: a block to be executed asynchronously

public func async(group: DispatchGroup, task: @escaping () -> Void)
{
  DispatchQueue.global(qos: .current).async(group: group, execute: task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter task: a block to be executed asynchronously

public func async(qos: DispatchQoS, task: @escaping () -> Void)
{
  DispatchQueue.global(qos: qos.qosClass).async(qos: qos, execute: task)
}

/// Utility shortcut for Grand Central Dispatch
///
/// - parameter qos: the quality-of-service class to associate to this block
/// - parameter group: a `DispatchGroup` to associate to this block execution
/// - parameter task: a block to be executed asynchronously

public func async(qos: DispatchQoS, group: DispatchGroup, task: @escaping () -> Void)
{
  DispatchQueue.global(qos: qos.qosClass).async(group: group, qos: qos, execute: task)
}


extension DispatchQoS.QoSClass
{
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  static var current: DispatchQoS.QoSClass {
    return DispatchQoS.QoSClass(rawValue: qos_class_self()) ?? .default
  }
  #else
  static var current: DispatchQoS.QoSClass {
    return .default
  }
  #endif
}
