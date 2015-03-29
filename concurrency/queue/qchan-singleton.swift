//
//  qchan-singleton.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  A one-element buffered channel which will only ever transmit one message:
  the first successful write operation closes the channel.

  The set of transmitted messages is (at most) a singleton set;
  not to be confused with the Singleton (anti?)pattern.
*/

final class QSingletonChan<T>: Chan<T>
{
  private var element: T? = nil

  // MARK: private housekeeping

  private var writerCount: Int32 = 0
  private var readerCount: Int32 = 0

  private let readerQueue = SuperSemaphoreQueue()

  private var lock = OS_SPINLOCK_INIT

  private var closedState: Int32 = 0

  override init()
  {
    super.init()
  }

  convenience init(_ element: T)
  {
    self.init()
    self.element = element
    writerCount = 1
    closedState = 1
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return readerCount == writerCount
  }

  final override var isFull: Bool
  {
    return readerCount < writerCount
  }

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closedState == 1 }

  // MARK: ChannelType methods

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  override func close()
  {
    if closedState == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &closedState)
    { // Only one thread can get here
      // Unblock waiting threads.
      signalNextReader()
    }
  }

  private func signalNextReader() -> Bool
  {
    OSSpinLockLock(&lock)
    while let ssema = readerQueue.dequeue()
    {
      switch ssema
      {
      case .semaphore(let s):
        OSSpinLockUnlock(&lock)
        dispatch_semaphore_signal(s)
        return true

      case .selection(let c, let selectionID):
        if let s = c.get()
        {
          OSSpinLockUnlock(&lock)
          let selection = Selection(id: selectionID)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          return true
        }
      }
    }
    OSSpinLockUnlock(&lock)
    return false
  }
  
  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if writerCount == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &writerCount)
    {
      element = newElement
      close() // also unblocks the first reader
      return true
    }

    // not the first writer, too late.
    return false
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closedState == 0
    {
      let s = dispatch_semaphore_create(0)!
      OSSpinLockLock(&lock)
      readerQueue.enqueue(s)
      OSSpinLockUnlock(&lock)
      dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER)

      signalNextReader()
    }

    if readerCount == 0 && OSAtomicCompareAndSwap32Barrier(0, 1, &readerCount)
    { // Only one thread can get here.
      if let e = element
      {
        element = nil
        return e
      }
    }

    return nil
  }

  // MARK: SelectableChannelType methods

  override func selectPutNow(selectionID: Selectable) -> Selection?
  {
    return writerCount == 0 ? Selection(id: selectionID) : nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    return put(newElement)
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable)
  {
    // If we get here, it would be as a result of an inconceivable set of circumstances.
    if let s = semaphore.get()
    {
      if self.writerCount == 0
      {
        let selection = Selection(id: selectionID)
        dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
      }
      dispatch_semaphore_signal(s)
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    return readerCount == 0 ? Selection(id: selectionID) : nil
  }

  override func extract(selection: Selection) -> T?
  {
    if readerCount == 0 && writerCount == 1 && OSAtomicCompareAndSwap32Barrier(0, 1, &readerCount)
    { // Only one thread can get here.
      if let e = element
      {
        element = nil
        return e
      }
    }
    return nil
  }
  
  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable)
  {
    if closedState == 1
    {
      if let s = semaphore.get()
      {
        let selection = Selection(id: selectionID)
        dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
        dispatch_semaphore_signal(s)
      }
    }
    else
    {
      OSSpinLockLock(&lock)
      readerQueue.enqueue(semaphore, id: selectionID)
      OSSpinLockUnlock(&lock)
    }
  }
}
