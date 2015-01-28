//
//  select-types.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  An evocative name for a closure type sent back by a selectReceive() method.
  Upon being run, a Signal should try to resume the thread spawned by selectReceive()
  if said thread happens to be blocked.

  This attempt may not always be successful, but if such cases the thread should
  eventually be resumed, because there would be several threads contending for the channel.
  There are situations where the Signal could be the only hope to resume the thread,
  because it is the only one waiting on its channel. In those cases the attempt should
  unblock the thread successfully.
*/

public typealias Signal = () -> ()
public let abortSelect = UnsafeMutablePointer<Void>(bitPattern: 1)

/**
  What a type needs to be usable in the Select() function.
*/

public protocol Selectable: class
{
  /**
    Select registers its notification channel by calling an implementation's selectReceive() method.
    This channel is a subtype of SingletonChannel and thus only one recipient will be able to respond.

    -> whatever code sends a notification back must run asynchronously.

    Associated data can be sent back along with the notification by copying it to the SelectChan.stash
    property. This (and sending the notification) can be done safely inside a closure that is invoked
    through the channel's SelectChan.channelMutex() method. This ensures that it runs synchronously
    with any other closures attempting to do the same, ensuring that only the first succeeds.

    :param: channel the channel to use for a return notification.
    :param: message an identifier to be sent as the return notification.
  
    :return: a closure to be run once, which can unblock a stopped thread if needed.
  */

  func selectNotify(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal

  /**
    If it makes no sense to invoke the selectReceive() method at this time, return false.
    If every Selectable in the list returns false, Select will assume that it should stop.
  */

  var selectable: Bool { get }
}

/**
  A particular kind of Anything.
*/

//public protocol SelectionType: class
//{
////  var selectable: Selectable { get }
////  func getMessageID() -> Selectable
//}

/**
  A channel that is Selectable should know how to extract data from one of these.
  After all, it should have created the object in its selectReceive() method.
*/

protocol SelectableChannelType: ChannelType
{
  func selectGet(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal
//  func extract(item: Selection) -> Element?

  func selectPut(semaphore: SingletonChan<dispatch_semaphore_t>, selectionID: Selectable) -> Signal
//  func insert(item: Selection) -> Bool
}

/**
  A special kind of SingletonChan for use by Select.
  SelectChan provides a way for a receiving channel to communicate back in a thread-safe
  way by using the selectSend() method within a closure passed to selectMutex().

  This would be better as an internal type.
*/

//public class SelectChan<T>: SingletonChan<T>, SelectingChannel
//{
//  typealias SentElement = T
//
//  override init()
//  {
//    super.init()
//  }
//}

/**
  Some extra interface for SelectChan.
  These methods have to be defined alongside the internals of SelectChan's superclass(es)
*/

//public protocol SelectingChannel
//{
//  typealias SentElement
//
//  /**
//    selectMutex() must be used to send data to SelectChan in a thread-safe manner
//
//    Actions which must be performed synchronously with the SelectChan should be passed to
//    selectMutex() as a closure. The closure will only be executed if the channel is still open.
//  */
//
//  func selectMutex(action: () -> ())
//
//  /**
//    selectSend() will send data to a SelectChan.
//    It must be called within the closure sent to selectMutex() for thread safety.
//    By definition, this call occurs while the channel's mutex is locked for the current thread.
//  */
//
//  func selectSend(newElement: SentElement)
//}

/**
  You can put anything in a Selection.
  It has a convenient, non-generic type.
  And it has a decidedly generic accessor method.
*/

public class Selection
{
  private let id: Selectable
  private let data: Any? = nil

  public init<T>(selectionID: Selectable, selectionData: T?)
  {
    id = selectionID
    if let d = selectionData
    {
      data = d
    }
  }

  public func getData<T>() -> T?
  {
    return data as? T
  }

  public var messageID: Selectable { return id }
}
