//
//  select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  `select()` gets notified of events by the first of a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified.

  - parameter `options`: a list of `Selectable` instances
  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select(options: Selectable...) -> Selection?
{
  return select(options, withDefault: nil)
}

/**
  `select()` gets notified of events by the first of a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified, unless `noBlocking` is `true`.
  In that case `select()`'s return value will not match any of the items in `options`.

  - parameter `options`:    a list of `Selectable` instances
  - parameter `noBlocking`: whether or not to allow blocking.

  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select(options: [Selectable], noBlocking: Bool) -> Selection?
{
  switch noBlocking
  {
  case true:  return select(options, withDefault: voidReceiver)
  case false: return select(options, withDefault: nil)
  }
}

/**
  `select()` gets notified of events by the first of a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified.
  If a default `Selectable` is set (i.e. not `nil`), `select()` will not block.

  - parameter `options`: a list of `Selectable` instances
  - parameter `withDefault`: a `Selectable` to return instead of waiting -- `nil` unless explicitly set.

  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select(options: [Selectable], withDefault: Selectable? = nil) -> Selection?
{
  let selectables = options.filter { $0.selectable }

  if selectables.count < 1
  { // Nothing left to do
    return nil
  }

  let semaphore = SemaphorePool.Obtain()
  semaphore.setState(.WaitSelect)

  for option in selectables.shuffle()
  {
    option.selectNotify(semaphore, selection: Selection(id: option))
    if semaphore.state != .WaitSelect { break }
  }

  if let def = withDefault where semaphore.setState(.Invalidated)
  {
    SemaphorePool.Return(semaphore)
    return Selection(id: def)
  }

  semaphore.wait()
  // We have a result
  let selection: Selection
  switch semaphore.state
  {
  case .Select:
    selection = semaphore.selection ?? voidSelection
    semaphore.selection = nil
    semaphore.setState(.Done)

  case .DoubleSelect:
    // this is specific to the extract() side of a double select.
    selection = semaphore.selection ?? voidSelection

  case .Invalidated, .Done:
    selection = voidSelection

  case let status: // default
    preconditionFailure("Unexpected ChannelSemaphore state (\(status)) in __FUNCTION__")
  }

  SemaphorePool.Return(semaphore)

  return selection
}

private let voidReceiver = Receiver<()>()
private let voidSelection = Selection(id: voidReceiver)
