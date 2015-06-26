//
//  select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  `select_chan()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select_chan()` will block until it gets notified.

  - parameter options: a list of `Selectable` instances
  - returns: a Selection that contains a `Selectable` along with possible parameters.
*/

public func select_chan(options: Selectable...) -> Selection?
{
  return select_chan(options, withDefault: nil)
}

/**
  `select_chan()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select_chan()` will block until it gets notified, unless `noBlocking` is `true`.
  In that case `select_chan()`'s return value will not match any of the items in `options`.

  - parameter options: an array of `Selectable` instances
  - parameter preventBlocking: whether or not to allow blocking.

  - returns: a `Selection` that contains a `Selectable` along with possible parameters.
*/

public func select_chan(options: [Selectable], preventBlocking: Bool) -> Selection?
{
  switch preventBlocking
  {
  case true:  return select_chan(options, withDefault: sink)
  case false: return select_chan(options, withDefault: nil)
  }
}

/**
  `select_chan()` gets notified of events by the first to be ready in a list of Selectable items.
  If no event is immediately available, `select_chan()` will block until it gets notified.

  If the `withDefault` parameter is set (i.e. not `nil`), `select_chan()` will not block, and will
  select `withDefault` instead.

  `select_chan()` operates thusly:
  1. All the items in `options` are visited in a random order and passed a reference that will
     enable them to notify the main thread that they are ready to be selected (that is, ready to send or receive.)
  2. As soon as one of them is ready to proceed (the notification is thread-safe,) the appropriate reference is
     stored in a new `Selection` struct, along with a `ChannelSemaphore` reference if it was set in the notification.
  3. The `Selection` is returned.

  The thread that runs `select_chan()` must then flow-control on the `Selection`'s `id` field, and compare it to
  the members of the `options` array. Finally, the operation can complete. A `Receiver` calls `extract()`,
  a `Sender` calls `insert()`. Other types of `Selectable` are surely possible.

  - parameter options: an array of `Selectable` instances
  - parameter withDefault: a `Selectable` that will be selected instead of blocking -- defaults to `nil`

  - returns: a `Selection` that contains a `Selectable` along with a possible `ChannelSemaphore`.
*/

public func select_chan(options: [Selectable], withDefault: Selectable? = nil) -> Selection?
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
