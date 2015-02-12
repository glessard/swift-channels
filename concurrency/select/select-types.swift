//
//  select-types.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  An evocative name for a closure type sent back by a selectNotify() method.
  Upon being run, a Signal should try to resume the thread spawned by selectNotify()
  if said thread happens to be blocked.

  This attempt may not always be directly successful, but in such cases the thread should
  eventually be resumed, because there would be several threads contending for the channel.
  There are situations where the Signal could be the only hope to resume the thread,
  because it is the only one waiting on its channel. In all such cases the attempt must
  unblock the thread successfully.
*/

public typealias Signal = () -> ()

/**
  A useful fake pointer for use with dispatch_set_context() in Signal closures.
*/

public let abortSelect = UnsafeMutablePointer<Void>(bitPattern: 1)

/**
  What a type needs to be usable in the Select() function.
*/

public protocol Selectable: class
{
  /**
    Select registers its notification semaphore by calling an implementation's selectNotify() method.

    -> whatever code sends a notification back must run asynchronously.

    Associated data can be sent back along with the semaphore by copying an 'Unmanaged' reference to
    a Selection via the semaphore's Context property (dispatch_set_context()).

    ***
    let selection = Selection(selectionID: selectionID, selectionData: element)
    let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
    dispatch_set_context(s, context)
    dispatch_semaphore_signal(s)
    ***

    Only one attempty to obtain the semaphore can succeed, thus one and only one Selectable can
    return data for each given invocation of Select().

    selectNotify launches a block of code for background execution, which is likely to block
    while waiting for data. selectNotify must return a closure capable of unblocking a thread
    waiting in the background. This paragraph is like word soup.

    :param: channel a channel from which to obtain a semaphore to use for a return notification.
    :param: message an identifier to be used to identify the return notification.
  
    :return: a closure to be run once, which can unblock a stopped thread if needed.
  */

  func selectNotify(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal

  /*
    Select first iterates through its Selectables to find whether at least one of them is ready
    This is much faster than launching N threads, triggering a race, and then getting all threads to
    be canceled.
  */

  func selectNow(selectionID: Selectable) -> Selection?

  /**
    If it makes no sense to invoke the selectNotify() method at this time, return false.
    If every Selectable in the list returns false, Select will stop by returning nil.
  */

  var selectable: Bool { get }
}

protocol SelectableChannelType: ChannelType
{
  func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  func selectGetNow(selectionID: Selectable) -> Selection?
  // func extract(item: Selection) -> Element?

  func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  func selectPutNow(selectionID: Selectable) -> Selection?
  func insert(ref: Selection, item: Element) -> Bool
}


/**
  You can put anything in a Selection.
  It has a convenient, non-generic type,
  coupled to a decidedly generic accessor method.
*/

public class Selection
{
  private let id: Selectable
  private let data: Any?

  public init<T>(selectionID: Selectable, selectionData: T?)
  {
    id = selectionID
    if let d = selectionData
    {
      data = d
    }
    else
    {
      data = nil
    }
  }

  public init(selectionID: Selectable)
  {
    id = selectionID
    data = nil
  }

  public func getData<T>() -> T?
  {
    return data as? T
  }

  public var messageID: Selectable { return id }
}
