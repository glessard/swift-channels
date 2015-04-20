//
//  select-types.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-28.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  What a type needs to be usable in the Select() function.
*/

// MARK: Selectable

public protocol Selectable: class
{
  /**
    Select registers its notification semaphore by calling an implementation's selectNotify() method.

    Associated data can be sent back along with the semaphore by copying an 'Unmanaged' reference to
    a Selection via the semaphore's Context property (dispatch_set_context()).

    ***
    let selection = Selection(selectionID: selectionID)
    let context = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
    dispatch_set_context(s, context)
    dispatch_semaphore_signal(s)
    ***

    Only one attempty to obtain the semaphore can succeed, since it is obtained from a buffered channel
    that contains a single element and is closed. Therefore one and only one Selectable can
    return data for each given invocation of Select().

    :param: channel a channel from which to obtain a semaphore to use for a return notification.
    :param: message an identifier to be used to identify the return notification.
  
    :return: a closure to be run once, which can unblock a stopped thread if needed.
  */

  func selectNotify(select: ChannelSemaphore, selection: Selection)

  /*
    Select first iterates through its Selectables to find whether at least one of them is ready.
    This is much faster than launching N threads, having them race to get the semaphore,
    and then getting the N-1 losing threads to be canceled.
  */

  func selectNow(selection: Selection) -> Selection?

  /**
    If it makes no sense to invoke the selectNotify() method at this time, return false.
    If every Selectable in the list returns false, Select will stop by returning nil.
  */

  var selectable: Bool { get }
}

// MARK: SelectableChannelType

protocol SelectableChannelType: ChannelType
{
  func selectGet(select: ChannelSemaphore, selection: Selection)
  func selectGetNow(selection: Selection) -> Selection?
  func extract(selection: Selection) -> Element?

  func selectPut(select: ChannelSemaphore, selection: Selection)
  func selectPutNow(selection: Selection) -> Selection?
  func insert(selection: Selection, newElement: Element) -> Bool
}

// MARK: SelectableReceiverType

public protocol SelectableReceiverType: ReceiverType, Selectable
{
  func extract(selection: Selection) -> ReceivedElement?
}

// MARK: SelectableSenderType

public protocol SelectableSenderType: SenderType, Selectable
{
  func insert(selection: Selection, newElement: SentElement) -> Bool
}


/**
  Selection is used to communicate references back to the select() function.
*/

public struct Selection
{
  public unowned let id: Selectable
  public let semaphore: ChannelSemaphore?

  public init(id: Selectable, semaphore: ChannelSemaphore)
  {
    self.id = id
    self.semaphore = semaphore
  }

  public init(id: Selectable)
  {
    self.id = id
    semaphore = nil
  }

  public func withSemaphore(semaphore: ChannelSemaphore) -> Selection
  {
    return Selection(id: self.id, semaphore: semaphore)
  }
}

enum SuperSemaphore
{
  case semaphore(ChannelSemaphore)
  case selection(ChannelSemaphore, Selection)
}

struct QueuedSemaphore
{
  let sem: ChannelSemaphore
  let sel: Selection?

  init(_ s: ChannelSemaphore)
  {
    sem = s
    sel = nil
  }

  init(_ sem: ChannelSemaphore, _ sel: Selection)
  {
    self.sem = sem
    self.sel = sel
  }
}
