//
//  qchan-unbuffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  An unbuffered channel that uses a queue of semaphores for scheduling.
*/

final class QUnbufferedChan<T>: Chan<T>
{
  // MARK: private housekeeping

  private let readerQueue = FastQueue<SuperSemaphore>()
  private let writerQueue = FastQueue<SuperSemaphore>()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return true
  }

  final override var isFull: Bool
  {
    return true
  }

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }

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
    if closed { return }

    OSSpinLockLock(&lock)
    closed = true

    // Unblock the threads waiting on our conditions.
    while let rs = readerQueue.dequeue()
    {
      switch rs
      {
      case .semaphore(let s):
        s.setState(.Done)
        s.signal()

      case .selection(let select, _):
        if select.setState(.Invalidated)
        {
          select.signal()
        }
      }
    }
    while let ws = writerQueue.dequeue()
    {
      switch ws
      {
      case .semaphore(let s):
        s.setState(.Done)
        s.signal()

      case .selection(let select, _):
        if select.setState(.Invalidated)
        {
          select.signal()
        }
      }
    }
    OSSpinLockUnlock(&lock)
  }


  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(var newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    while let rss = readerQueue.dequeue()
    { // there is already an interested reader
      switch rss
      {
      case .semaphore(let rs):
        OSSpinLockUnlock(&lock)
        switch rs.state
        {
        case .Pointer:
          // attach a new copy of our data to the reader's semaphore
          rs.getPointer().initialize(newElement)
          rs.signal()
          return true

        case let state: // default
          preconditionFailure("Unexpected Semaphore state \(state) in \(__FUNCTION__)")
        }

      case .selection(let select, let selection):
        if select.setState(.DoubleSelect)
        { // pass the data on to an extract()
          OSSpinLockUnlock(&lock)
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          buffer.initialize(newElement)
          // buffer will be cleaned up in the .DoubleSelect case of extract()

          select.selection = selection.withSemaphore(select)
          select.setPointer(buffer)
          select.signal()

          // the data was passed on; it must have been successful.
          // if not, select() or extract() are likely to complain, or memory will leak.
          return true
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // make our data available for a reader
    let threadLock = SemaphorePool.Obtain()
    threadLock.setState(.Pointer)
    threadLock.setPointer(&newElement)
    writerQueue.enqueue(.semaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    let state = threadLock.state
    let match = threadLock.getPointer() == &newElement
    threadLock.setState(.Done)
    SemaphorePool.Return(threadLock)

    switch state
    {
    case .Done:
      // thread was awoken by close() and put() has failed
      return false

    case .Pointer where match:
      // the message was succesfully passed.
      return match

    default:
      preconditionFailure("Unexpected Semaphore state \(state) after wait in \(__FUNCTION__)")
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed { return nil }

    OSSpinLockLock(&lock)

    while let wss = writerQueue.dequeue()
    { // data is already available
      switch wss
      {
      case .semaphore(let ws):
        OSSpinLockUnlock(&lock)
        switch ws.state
        {
        case .Pointer:
          let element: T = ws.getPointer().memory
          ws.signal()
          return element

        case let state:
          preconditionFailure("Unexpected Semaphore state \(state) in \(__FUNCTION__)")
        }

      case .selection(let select, let selection):
        let threadLock = SemaphorePool.Obtain()
        if select.setState(.Select)
        { // get data from an insert()
          OSSpinLockUnlock(&lock)
          select.selection = selection.withSemaphore(threadLock)
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          threadLock.setState(.Pointer)
          threadLock.setPointer(buffer)
          select.signal()
          threadLock.wait()

          // got awoken by insert()
          let state = threadLock.state
          let match = threadLock.getPointer() == buffer
          threadLock.setState(.Done)
          SemaphorePool.Return(threadLock)

          switch state
          {
          case .Pointer where match:
            let element = buffer.move()
            buffer.dealloc(1)
            return element

          default:
            preconditionFailure("Unexpected Semaphore state \(state) in \(__FUNCTION__)")
          }
        }
        SemaphorePool.Return(threadLock)
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    // wait for data from a writer
    let threadLock = SemaphorePool.Obtain()
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    threadLock.setState(.Pointer)
    threadLock.setPointer(buffer)
    readerQueue.enqueue(.semaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    let state = threadLock.state
    let match = threadLock.getPointer() == buffer
    threadLock.setState(.Done)
    SemaphorePool.Return(threadLock)

    switch state
    {
    case .Done:
      // thread was awoken by close(): no more data on the channel.
      buffer.dealloc(1)
      return nil

    case .Pointer where match:
      let element = buffer.move()
      buffer.dealloc(1)
      return element

    default:
      preconditionFailure("Unknown state (\(state)) after wait in \(__FUNCTION__)")
    }
  }

  // MARK: SelectableChannelType methods

  override func selectPutNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    while let rss = readerQueue.dequeue()
    {
      switch rss
      {
      case .semaphore(let rs):
        OSSpinLockUnlock(&lock)
        return selection.withSemaphore(rs)

      case .selection(let extractSelect, let extractSelection):
        if extractSelect.setState(.DoubleSelect)
        {
          OSSpinLockUnlock(&lock)
          extractSelect.selection = extractSelection.withSemaphore(extractSelect)
          extractSelect.setPointer(UnsafeMutablePointer<T>.alloc(1))

          return selection.withSemaphore(extractSelect)
        }
        // try the next enqueued reader instead
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    if let rs = selection.semaphore
    {
      switch rs.state
      {
      case .Pointer, .DoubleSelect:
        // attach a new copy of our data to the reader's semaphore
        rs.getPointer().initialize(newElement)
        rs.signal()
        return true

      case let state: // default
        preconditionFailure("Unexpected state (\(state)) in \(__FUNCTION__)")
      }
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(selection)")
    return false
  }

  override func selectPut(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let rss = readerQueue.dequeue()
    {
      switch rss
      {
      case .semaphore(let rs):
        if select.setState(.Select)
        {
          OSSpinLockUnlock(&lock)
          select.selection = selection.withSemaphore(rs)
          select.signal()
        }
        else
        {
          readerQueue.undequeue(rss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let extractSelect, let extractSelection):
        if extractSelect.state == .WaitSelect
        {
          if select.setState(.Select)
          {
            OSSpinLockUnlock(&lock)
            if extractSelect.setState(.DoubleSelect)
            {
              extractSelect.selection = extractSelection.withSemaphore(extractSelect)
              extractSelect.setPointer(UnsafeMutablePointer<T>.alloc(1))

              select.selection = selection.withSemaphore(extractSelect)
              select.signal()
            }
            else
            { // failed to get both semaphores in the appropriate state at the same time
              select.setState(.Done)
              select.signal()
            }
          }
          else
          {
            readerQueue.undequeue(rss)
            OSSpinLockUnlock(&lock)
          }
          return
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.Invalidated)
      {
        select.signal()
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    writerQueue.enqueue(.selection(select, selection))
    OSSpinLockUnlock(&lock)
  }

  override func selectGetNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    while let wss = writerQueue.dequeue()
    {
      switch wss
      {
      case .semaphore(let ws):
        OSSpinLockUnlock(&lock)
        return selection.withSemaphore(ws)

      case .selection(let insertSelect, _):
        if insertSelect.state == .WaitSelect
        { // the "get" side of a double select *cannot* complete in a reasonable time,
          // therefore defer until the asynchronous phase of select.
          // the insert side might win the race?
          writerQueue.undequeue(wss)
          OSSpinLockUnlock(&lock)
          return nil
        }
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func extract(selection: Selection) -> T?
  {
    if let ws = selection.semaphore
    {
      switch ws.state
      {
      case .Pointer:
        let element: T = ws.getPointer().memory
        ws.signal()
        return element

      case .DoubleSelect:
        let pointer = UnsafeMutablePointer<T>(ws.pointer)
        let element: T = pointer.move()
        pointer.dealloc(1)
        ws.pointer = nil
        ws.selection = nil
        ws.setState(.Done)
        return element

      case let state: // default
        preconditionFailure("Unexpected state (\(state)) in \(__FUNCTION__)")
      }
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(selection)")
    return nil
  }

  override func selectGet(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let wss = writerQueue.dequeue()
    {
      switch wss
      {
      case .semaphore(let ws):
        if select.setState(.Select)
        {
          OSSpinLockUnlock(&lock)
          select.selection = selection.withSemaphore(ws)
          select.signal()
        }
        else
        {
          writerQueue.undequeue(wss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let insertSelect, let insertSelection):
        if insertSelect.state == .WaitSelect
        {
          if select.setState(.DoubleSelect)
          {
            OSSpinLockUnlock(&lock)
            if insertSelect.setState(.Select)
            { // prepare select
              select.selection = selection.withSemaphore(select)
              select.setPointer(UnsafeMutablePointer<T>.alloc(1))

              insertSelect.selection = insertSelection.withSemaphore(select)
              insertSelect.signal()
            }
            else
            { // failed to get both semaphores in the right state at the same time
              select.setState(.Done)
              select.signal()
            }
          }
          else
          {
            writerQueue.undequeue(wss)
            OSSpinLockUnlock(&lock)
          }
          return
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.Invalidated)
      {
        select.signal()
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    readerQueue.enqueue(.selection(select, selection))
    OSSpinLockUnlock(&lock)
  }
}
