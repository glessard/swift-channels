//
//  qchan-unbuffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

/**
  An unbuffered channel that uses a queue of semaphores for scheduling.
*/

final class QUnbufferedChan<T>: Chan<T>
{
  // MARK: private housekeeping

  private let readerQueue = SuperSemaphoreQueue()
  private let writerQueue = SuperSemaphoreQueue()

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
        s.setStatus(.Empty)
        s.signal()

      case .selection(let select, _):
        if select.setStatus(.Invalidated)
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
        s.setStatus(.Empty)
        s.signal()

      case .selection(let select, _):
        if select.setStatus(.Invalidated)
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
        switch rs.status
        {
        case .Pointer(let buffer):
          // attach a new copy of our data to the reader's semaphore
          UnsafeMutablePointer<T>(buffer).initialize(newElement)
          rs.signal()
          return true

        case let status: // default
          preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
        }

      case .selection(let select, let originalSelection):
        let threadLock = SemaphorePool.Obtain()
        let selection = originalSelection.withSemaphore(threadLock)
        if select.setStatus(.Select(selection))
        { // pass the data on to an insert()
          OSSpinLockUnlock(&lock)
          threadLock.setStatus(.Pointer(&newElement))
          select.signal()
          threadLock.wait()

          // got awoken by insert()
          let status = threadLock.status
          SemaphorePool.Return(threadLock)

          switch status
          {
          case .Pointer(let pointer) where pointer == &newElement:
            return true

          default:
            preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
          }
        }
        SemaphorePool.Return(threadLock)
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // make our data available for a reader
    let threadLock = SemaphorePool.Obtain()
    threadLock.setStatus(.Pointer(&newElement))
    writerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    let status = threadLock.status
    threadLock.setStatus(.Empty)
    SemaphorePool.Return(threadLock)

    switch status
    {
    case .Empty:
      // thread was awoken by close() and put() has failed
      return false

    case .Pointer(let pointer) where pointer == &newElement:
      // the message was succesfully passed.
      return true

    default:
      preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
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
        switch ws.status
        {
        case .Pointer(let pointer):
          let element: T = UnsafePointer(pointer).memory
          ws.signal()
          return element

        case let status:
          preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
        }

      case .selection(let select, let originalSelection):
        let threadLock = SemaphorePool.Obtain()
        if select.setStatus(.Select(originalSelection.withSemaphore(threadLock)))
        { // get data from an extract()
          OSSpinLockUnlock(&lock)
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          threadLock.setStatus(.Pointer(buffer))
          select.signal()
          threadLock.wait()

          // got awoken by extract()
          let status = threadLock.status
          SemaphorePool.Return(threadLock)

          switch status
          {
          case .Pointer(let pointer) where pointer == buffer:
            let element = buffer.move()
            buffer.dealloc(1)
            return element

          default:
            preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
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
    threadLock.setStatus(.Pointer(buffer))
    readerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    let status = threadLock.status
    threadLock.setStatus(.Empty)
    SemaphorePool.Return(threadLock)

    switch status
    {
    case .Empty:
      // thread was awoken by close(): no more data on the channel.
      buffer.dealloc(1)
      return nil

    case .Pointer(let pointer) where pointer == buffer:
      let element = buffer.move()
      buffer.dealloc(1)
      return element

    default:
      preconditionFailure("Unknown status (\(status)) after sleep state in \(__FUNCTION__)")
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
        let intermediary = SemaphorePool.Obtain()
        let newExtractSelection = extractSelection.withSemaphore(intermediary)
        if extractSelect.setStatus(.Select(newExtractSelection))
        {
          OSSpinLockUnlock(&lock)
          insertToExtract(extractSelect, intermediary)
          return selection.withSemaphore(intermediary)
        }
        SemaphorePool.Return(intermediary)
        // try the next enqueued reader instead
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func insertToExtract(extractSelect: ChannelSemaphore, _ intermediary: ChannelSemaphore)
  {
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    intermediary.setStatus(.Pointer(buffer))

    // two select()s talking to each other need a 3rd thread
    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      intermediary.wait()
      // got awoken by insert()
      // precondition(dispatch_get_context(intermediary) == buffer, "Unknown context in \(__FUNCTION__)")

      extractSelect.signal()
      intermediary.wait()
      // got awoken by extract(). clean up.
      buffer.destroy(1)
      buffer.dealloc(1)
      SemaphorePool.Return(intermediary)
    }
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    if let rs = selection.semaphore
    {
      switch rs.status
      {
      case .Pointer(let pointer):
        UnsafeMutablePointer<T>(pointer).initialize(newElement)
        rs.signal()
        return true

      case let status: // default
        preconditionFailure("Unexpected status (\(status)) in \(__FUNCTION__)")
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
        if select.setStatus(.Select(selection.withSemaphore(rs)))
        {
          OSSpinLockUnlock(&lock)
          select.signal()
        }
        else
        {
          readerQueue.undequeue(rss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let extractSelect, let extractSelection):
        let intermediary = SemaphorePool.Obtain()
        if select.setStatus(.Select(selection.withSemaphore(intermediary)))
        {
          OSSpinLockUnlock(&lock)
          let newExtractSelection = extractSelection.withSemaphore(intermediary)
          if extractSelect.setStatus(.Select(newExtractSelection))
          {
            insertToExtract(extractSelect, intermediary)
          }
          else
          {
            select.invalidate(match: intermediary)
            SemaphorePool.Return(intermediary)
          }
          select.signal()
          return
        }
        else
        {
          readerQueue.undequeue(rss)
          OSSpinLockUnlock(&lock)
          SemaphorePool.Return(intermediary)
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setStatus(.Invalidated)
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

      case .selection(let insertSelect, let insertSelection):
        let intermediary = SemaphorePool.Obtain()
        let newInsertSelection = insertSelection.withSemaphore(intermediary)
        if insertSelect.setStatus(.Select(newInsertSelection))
        {
          OSSpinLockUnlock(&lock)
          extractFromInsert(insertSelect, intermediary)
          return selection.withSemaphore(intermediary)
        }
        SemaphorePool.Return(intermediary)
        // try the next enqueued writer instead
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func extractFromInsert(insertSelect: ChannelSemaphore, _ intermediary: ChannelSemaphore)
  {
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    intermediary.setStatus(.Pointer(buffer))

    // get the buffer filled by insert()
    insertSelect.signal()
    intermediary.wait()
    // got awoken by insert()
    // precondition(dispatch_get_context(intermediary) == buffer, "Unknown context in \(__FUNCTION__)")

    // two select()s talking to each other need a 3rd thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
      intermediary.wait()
      // got awoken by extract(). clean up.
      buffer.destroy(1)
      buffer.dealloc(1)
      SemaphorePool.Return(intermediary)
    }
  }

  override func extract(selection: Selection) -> T?
  {
    if let ws = selection.semaphore
    {
      switch ws.status
      {
      case .Pointer(let pointer):
        let element: T = UnsafePointer(pointer).memory
        ws.signal()
        return element

      case let status: // default
        preconditionFailure("Unexpected status (\(status)) in \(__FUNCTION__)")
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
        if select.setStatus(.Select(selection.withSemaphore(ws)))
        {
          OSSpinLockUnlock(&lock)
          select.signal()
        }
        else
        {
          writerQueue.undequeue(wss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let insertSelect, let insertSelection):
        let intermediary = SemaphorePool.Obtain()
        if select.setStatus(.Select(selection.withSemaphore(intermediary)))
        {
          OSSpinLockUnlock(&lock)
          let newInsertSelection = insertSelection.withSemaphore(intermediary)
          if insertSelect.setStatus(.Select(newInsertSelection))
          {
            extractFromInsert(insertSelect, intermediary)
          }
          else
          {
            select.invalidate(match: intermediary)
            SemaphorePool.Return(intermediary)
          }
          select.signal()
          return
        }
        else
        {
          writerQueue.undequeue(wss)
          OSSpinLockUnlock(&lock)
          SemaphorePool.Return(intermediary)
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setStatus(.Invalidated)
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
