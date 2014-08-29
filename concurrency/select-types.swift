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
  func selectRead(channel: SelectChan<Selectable>, message: Selectable) -> Signal

  /**
    If it makes no sense to launch the selectRead() method, return false to this.
    If every Selectable in the list returns false, Select will assume that it should stop.
  */

  var  invalidSelection: Bool { get }
}

/**
  A particular kind of Anything.
*/

public protocol Selectee: class
{
}

/**
  A channel that is Selectable should know how to extract data from one of these.
  After all, it should have created the object in its selectRead() method.
*/

public protocol SelectableChannel: Selectable, ReadableChannel
{
  func extract(item: Selectee?) -> ReadElement?
}

/**
  A special kind of SingletonChan for use by Select.
  SelectChan provides a way for a receiving channel to "stash" its payload
  for later recovery upon return to the body of the Select function.
  This is a special case of cross-thread data sharing.
*/

public class SelectChan<T>: SingletonChan<T>
{
  private let gcdq: dispatch_queue_t
  private var payload: Selectee

  public override init()
  {
    gcdq = dispatch_queue_create("SelectChan", DISPATCH_QUEUE_SERIAL)
    let nilT: T? = nil
    payload = SelectPayload(payload: nilT)
    super.init()
  }

  var stash: Selectee
  {
    get { return payload }
    set { payload = newValue }
  }

  public func mutexAction(action: () -> ())
  {
    dispatch_sync(gcdq) { action() }
  }
}

/**
  You can put anything in here. And it has a non-generic type.
  It's like a Bag of Holding. For one thing at a time.
*/

public class SelectPayload<T>: Selectee
{
  var data: T?

  public init(payload: T?)
  {
    data = payload
  }
}
