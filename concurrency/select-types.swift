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

public typealias Signal = () -> ()

public protocol Selectable: class
{
  /**
    Select registers its notification channel by calling an implementation's selectRead() method.
    This channel is a subtype of SingletonChannel and thus only one recipient will be able to respond.

    -> whatever code sends a notification back should run asynchronously.

    Associated data can be sent back along with the notification by copying it to the SelectChan.stash
    property. This (and sending the notification) can be done safely inside a closure that is invoked
    through the channel's SelectChan.channelMutex() method. This ensures that it runs synchronously
    with any other closures attempting to do the same, ensuring that only the first succeeds.

    :param: channel the channel to use for a return notification.
    :param: message an identifier to be sent as the return notification.
  
    :return: a closure to be run once, which can unlock a stopped thread if needed.
  */

  func selectRead(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal

  /**
    If it makes no sense to launch the selectRead() method, return false to this.
    If every Selectable in the list returns false, Select will assume that it should stop.
  */

  var  invalidSelection: Bool { get }
}

/**
  A particular kind of Anything.
*/

public protocol SelectionType: class
{
//  var selectable: Selectable { get }
//  func getMessageID() -> Selectable
}

/**
  A channel that is Selectable should know how to extract data from one of these.
  After all, it should have created the object in its selectRead() method.
*/

public protocol SelectableChannel: class, Selectable, ReadableChannel
{
  func extract(item: SelectionType?) -> ReadElement?
}

/**
  A special kind of SingletonChan for use by Select.
  SelectChan provides a way for a receiving channel to communicate back in a thread-safe
  way by using the selectSend() method within a closure passed to selectMutex().
*/

public class SelectChan<T>: SingletonChan<T>, SelectionChannel
{
  override init()
  {
    super.init()
  }
}

/**
  Some extra interface for SelectChan.
  These methods have to be defined alongside the internals of SelectChan's superclass(es)
*/

public protocol SelectionChannel
{
  typealias WrittenElement

  /**
    selectMutex() must be used to send data to SelectChan in a thread-safe manner

    Actions which must be performed synchronously with the SelectChan should be passed to
    selectMutex() as a closure. The closure will only be executed if the channel is still open.
  */

  func selectMutex(action: () -> ())

  /**
    selectSend() will send data to a SelectChan.
    It must be called within the closure sent to selectMutex() for thread safety.
    By definition, this call occurs while the channel's mutex is locked for the current thread.
  */

  func selectSend(newElement: WrittenElement)
}

/**
  You can put anything in a Selection<T>.
  And it has a non-generic type in the form of a protocol.
  It's like a Bag of Holding. For one thing at a time.
*/

public class Selection<T>: SelectionType
{
  var messID: Selectable
  var data: T?

  public init(messageID: Selectable, messageData: T?)
  {
    messID = messageID
    data = messageData
  }

  public func getMessageID() -> Selectable { return messID }
}