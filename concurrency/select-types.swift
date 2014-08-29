//
//  chan-select.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  What a type needs to be usable in the Select() function.
*/

public protocol Selectable: class
{
  /**
    Select registers its notification channel by calling an implementation's selectRead() method.
    This channel is a subtype of SingletonChannel and thus only one recipient will be able to respond.

    Associated data can be sent back along with the notification by copying it to the SelectChan.stash
    property. This (and sending the notification) can be done safely inside a closure that is invoked
    through the channel's SelectChan.mutexAction() method. This ensures that it runs synchronously
    with any other closures attempting to do the same, ensuring that only the first succeeds.

    :param: channel the channel to use for a return notification.
    :param: message an identifier to be sent as the return notification.
  */
  func selectRead(channel: SelectChan<Selectable>, message: Selectable)
  var  invalidSelection: Bool { get }
}

/**
  This is a particular kind of Anything.
*/

public protocol Selectee: class
{
}

public protocol SelectableChannel: Selectable, ReadableChannel
{
  func extract(item: Selectee?) -> ReadElement?
}


public class SelectChan<T>: SingletonChan<T>
{
  private let gcdq: dispatch_queue_t
  private var payload: Selectee? = nil

  public override init()
  {
    gcdq = dispatch_queue_create("SelectChan", DISPATCH_QUEUE_SERIAL)
    super.init()
  }

  var stash: Selectee?
  {
    get { return payload }
    set { payload = newValue }
  }

  private var mutexActions = 0
  public func mutexAction(action: () -> ())
  {
    dispatch_sync(gcdq) { action() }

    self.mutexActions += 1
    syncprint("Attempted mutex action #\(mutexActions)")
  }
}

public class SelectPayload<T>: Selectee
{
  var p: T?

  public init(payload: T?)
  {
    p = payload
  }
}
