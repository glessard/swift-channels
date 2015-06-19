//
//  select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  `select()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified.

  - parameter options: a list of `Selectable` instances
  - returns: a Selection that contains a `Selectable` along with possible parameters.
*/

public func select(options: Selectable...) -> Selection?
{
  return select(options, withDefault: nil)
}

/**
  `select()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified, unless `noBlocking` is `true`.
  In that case `select()`'s return value will not match any of the items in `options`.

  - parameter options: an array of `Selectable` instances
  - parameter preventBlocking: whether or not to allow blocking.

  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select(options: [Selectable], preventBlocking: Bool) -> Selection?
{
  switch preventBlocking
  {
  case true:  return select(options, withDefault: sink)
  case false: return select(options, withDefault: nil)
  }
}

/**
  `select()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select()` will block until it gets notified.
  If the `withDefault` parameter is set (i.e. not `nil`), `select()` will not block, and will
  select `withDefault` instead.

  - parameter options: an array of `Selectable` instances
  - parameter withDefault: a `Selectable` that will be selected instead of blocking -- defaults to `nil`

  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select(options: [Selectable], withDefault: Selectable? = nil) -> Selection?
{
  let semaphore = SemaphorePool.Obtain()
  defer { SemaphorePool.Return(semaphore) }
  semaphore.setState(.WaitSelect)

  var selectables = 0
  for option in options.shuffle() where option.selectable
  {
    option.selectNotify(semaphore, selection: Selection(id: option))
    selectables += 1
    guard semaphore.state == .WaitSelect else { break }
  }
  if selectables == 0
  { // nothing left to do
    return nil
  }

  if let def = withDefault where semaphore.setState(.Invalidated)
  {
    return Selection(id: def)
  }

  semaphore.wait()
  // We have a result
  let selection: Selection
  switch semaphore.state
  {
  case .Select:
    selection = semaphore.selection
    semaphore.selection = nil
    semaphore.setState(.Done)

  case .DoubleSelect:
    // this is specific to the extract() side of a double select.
    selection = semaphore.selection

  case .Invalidated, .Done:
    selection = Selection(id: sink)

  case let status: // default
    preconditionFailure("Unexpected ChannelSemaphore state (\(status)) in __FUNCTION__")
  }
  return selection
}

private let sink = Sink<()>()
