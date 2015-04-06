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

      case .selection(let c, _):
        if let s = c.get()
        {
          dispatch_semaphore_signal(s)
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

      case .selection(let c, _):
        if let s = c.get()
        {
          dispatch_semaphore_signal(s)
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

      case .selection(let c, let originalSelection):
        if let s = c.get()
        { // pass the data on to an insert()
          OSSpinLockUnlock(&lock)
          let threadLock = SemaphorePool.Obtain()
          threadLock.setStatus(.Pointer(&newElement))
          let selection = Selection(id: originalSelection.id, semaphore: threadLock)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          threadLock.wait()

          // got awoken by insert()
          let status = threadLock.status
          threadLock.setStatus(.Empty)
          SemaphorePool.Return(threadLock)

          switch status
          {
          case .Pointer(let pointer) where pointer == &newElement:
            return true

          default:
            preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
          }
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

      case .selection(let c, let originalSelection):
        if let s = c.get()
        { // get data from an extract()
          OSSpinLockUnlock(&lock)
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          let threadLock = SemaphorePool.Obtain()
          threadLock.setStatus(.Pointer(buffer))
          let selection = Selection(id: originalSelection.id, semaphore: threadLock)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          threadLock.wait()
          // got awoken by extract()
          // precondition(dispatch_get_context(threadLock) == buffer, "Unknown context in \(__FUNCTION__)")

          threadLock.setStatus(.Empty)
          SemaphorePool.Return(threadLock)

          let element = buffer.move()
          buffer.dealloc(1)
          return element
        }
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

      case .selection(let c, let extractSelection):
        if let extractSelect = c.get()
        {
          OSSpinLockUnlock(&lock)
          return selection.withSemaphore(insertToExtract(extractSelect, extractSelection))
        }
        // try the next enqueued reader instead
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func insertToExtract(extractSelect: dispatch_semaphore_t, _ extractSelection: Selection) -> ChannelSemaphore
  {
    // We have two select() functions talking to eath other. They need an intermediary.
    let intermediary = SemaphorePool.Obtain()
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    intermediary.setStatus(.Pointer(buffer))

    // two select()s talking to each other need a 3rd thread
    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      intermediary.wait()
      // got awoken by insert()
      // precondition(dispatch_get_context(intermediary) == buffer, "Unknown context in \(__FUNCTION__)")

      let selection = Selection(id: extractSelection.id, semaphore: intermediary)
      dispatch_set_context(extractSelect, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
      dispatch_semaphore_signal(extractSelect)
      intermediary.wait()
      // got awoken by extract(). clean up.
      buffer.destroy(1)
      buffer.dealloc(1)
      intermediary.setStatus(.Empty)
      SemaphorePool.Return(intermediary)
    }

    // this return value will be sent off to insert()
    return intermediary
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

  override func selectPut(semaphore: SemaphoreChan, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let rss = readerQueue.dequeue()
    {
      switch rss
      {
      case .semaphore(let rs):
        if let select = semaphore.get()
        {
          OSSpinLockUnlock(&lock)
          let newSelection = selection.withSemaphore(rs)
          dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(newSelection).toOpaque()))
          dispatch_semaphore_signal(select)
        }
        else
        {
          readerQueue.undequeue(rss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let c, let extractSelection):
        if !c.isEmpty
        {
          if let select = semaphore.get()
          {
            OSSpinLockUnlock(&lock)
            if let extractSelect = c.get()
            {
              let newSelection = selection.withSemaphore(insertToExtract(extractSelect, extractSelection))
              dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(newSelection).toOpaque()))
            }
            dispatch_semaphore_signal(select)
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
      if let select = semaphore.get()
      {
        dispatch_semaphore_signal(select)
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    writerQueue.enqueue(.selection(semaphore, selection))
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

      case .selection(let c, let insertSelection):
        if let insertSelect = c.get()
        {
          OSSpinLockUnlock(&lock)
          return selection.withSemaphore(extractFromInsert(insertSelect, insertSelection))
        }
        // try the next enqueued writer instead
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func extractFromInsert(insertSelect: dispatch_semaphore_t, _ insertSelection: Selection) -> ChannelSemaphore
  {
    // We have two select() functions talking to eath other. They need an intermediary.
    let intermediary = SemaphorePool.Obtain()
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    intermediary.setStatus(.Pointer(buffer))

    // get the buffer filled by insert()
    let selection = Selection(id: insertSelection.id, semaphore: intermediary)
    dispatch_set_context(insertSelect, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
    dispatch_semaphore_signal(insertSelect)
    intermediary.wait()
    // got awoken by insert()
    // precondition(dispatch_get_context(intermediary) == buffer, "Unknown context in \(__FUNCTION__)")

    // two select()s talking to each other need a 3rd thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
      intermediary.wait()
      // got awoken by extract(). clean up.
      buffer.destroy(1)
      buffer.dealloc(1)
      intermediary.setStatus(.Empty)
      SemaphorePool.Return(intermediary)
    }

    // this return value will be sent off to extract()
    return intermediary
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

  override func selectGet(semaphore: SemaphoreChan, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let wss = writerQueue.dequeue()
    {
      switch wss
      {
      case .semaphore(let ws):
        if let select = semaphore.get()
        {
          OSSpinLockUnlock(&lock)
          let newSelection = selection.withSemaphore(ws)
          dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(newSelection).toOpaque()))
          dispatch_semaphore_signal(select)
        }
        else
        {
          writerQueue.undequeue(wss)
          OSSpinLockUnlock(&lock)
        }
        return

      case .selection(let c, let insertSelection):
        if !c.isEmpty
        {
          if let select = semaphore.get()
          {
            OSSpinLockUnlock(&lock)
            if let insertSelect = c.get()
            {
              let newSelection = selection.withSemaphore(extractFromInsert(insertSelect, insertSelection))
              dispatch_set_context(select, UnsafeMutablePointer<Void>(Unmanaged.passRetained(newSelection).toOpaque()))
            }
            dispatch_semaphore_signal(select)
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
      if let select = semaphore.get()
      {
        dispatch_semaphore_signal(select)
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    readerQueue.enqueue(.selection(semaphore, selection))
    OSSpinLockUnlock(&lock)
  }
}
