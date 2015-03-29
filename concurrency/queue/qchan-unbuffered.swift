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
        dispatch_set_context(s, nil)
        dispatch_semaphore_signal(s)

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
        dispatch_set_context(s, nil)
        dispatch_semaphore_signal(s)

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

    if let ss = readerQueue.dequeue()
    { // there is already an interested reader
      OSSpinLockUnlock(&lock)
      switch ss
      {
      case .semaphore(let rs):
        switch dispatch_get_context(rs)
        {
        case nil:
          preconditionFailure(__FUNCTION__)

        case let buffer: // default
          // attach a new copy of our data to the reader's semaphore
          UnsafeMutablePointer<T>(buffer).initialize(newElement)
          dispatch_semaphore_signal(rs)
          return true
        }

      case .selection(let c, let selectionID):
        if let s = c.get()
        { // pass the data on to an insert()
          let threadLock = SemaphorePool.dequeue()
          dispatch_set_context(threadLock, &newElement)
          let selection = Selection(id: selectionID, semaphore: threadLock)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

          // got awoken
          let context = dispatch_get_context(threadLock)
          dispatch_set_context(threadLock, nil)
          SemaphorePool.enqueue(threadLock)

          switch context
          {
          case &newElement:
            return true

          default:
            preconditionFailure("Unknown context value (\(context)) in \(__FUNCTION__) on return from insert()")
          }
        }
        else
        {
          return self.put(newElement)
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // make our data available for a reader
    let threadLock = SemaphorePool.dequeue()
    dispatch_set_context(threadLock, &newElement)
    writerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = dispatch_get_context(threadLock)
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)

    switch context
    {
    case nil:
      // thread was awoken by close() and put() has failed
      return false

    case &newElement:
      // the message was succesfully passed.
      return true

    default:
      preconditionFailure("Unknown context value (\(context)) after sleep state in \(__FUNCTION__)")
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

    if let ss = writerQueue.dequeue()
    { // data is already available
      OSSpinLockUnlock(&lock)

      switch ss
      {
      case .semaphore(let ws):
        switch dispatch_get_context(ws)
        {
        case nil:
          preconditionFailure(__FUNCTION__)

        case let context: // default
          // copy data from a pointer to a variable stored "on the stack"
          let element: T = UnsafePointer(context).memory
          dispatch_semaphore_signal(ws)
          return element
        }

      case .selection(let c, let selectionID):
        if let s = c.get()
        { // pass the data on to an extract()
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          let threadLock = SemaphorePool.dequeue()
          dispatch_set_context(threadLock, buffer)
          let selection = Selection(id: selectionID, semaphore: threadLock)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

          // got awoken
          let context = dispatch_get_context(threadLock)
          dispatch_set_context(threadLock, nil)
          SemaphorePool.enqueue(threadLock)

          switch context
          {
          case buffer:
            let element = buffer.move()
            buffer.dealloc(1)
            return element

          default:
            preconditionFailure("Unknown context value (\(context)) in \(__FUNCTION__) on return from extract()")
          }
        }
        else
        {
          return self.get()
        }
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    // wait for data from a writer
    let threadLock = SemaphorePool.dequeue()
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    dispatch_set_context(threadLock, buffer)
    readerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = dispatch_get_context(threadLock)
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)

    switch context
    {
    case nil:
      // thread was awoken by close(): no more data on the channel.
      buffer.dealloc(1)
      return nil

    case buffer:
      let element = buffer.move()
      buffer.dealloc(1)
      return element

    default:
      preconditionFailure("Unknown context value (\(context)) after sleep state in \(__FUNCTION__)")
    }
  }

  // MARK: SelectableChannelType methods

  override func selectPutNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let rs = selectPutNow()
    {
      OSSpinLockUnlock(&lock)
      return Selection(id: selectionID, semaphore: rs)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func selectPutNow() -> dispatch_semaphore_t?
  {
    precondition(lock != 0, __FUNCTION__)
    while let ssema = readerQueue.dequeue()
    {
      switch ssema
      {
      case .semaphore(let rs):
        return rs

      case .selection(let c, let selectionID):
        if let s = c.get()
        {
          OSSpinLockUnlock(&lock)
          let mediator = SemaphorePool.dequeue()
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          dispatch_set_context(mediator, buffer)

          // two select()s talking to each other need a 3rd thread
          dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
            dispatch_semaphore_wait(mediator, DISPATCH_TIME_FOREVER)
            // got awoken by insert()
            precondition(dispatch_get_context(mediator) == buffer, "Unknown context in \(__FUNCTION__)")

            let selection = Selection(id: selectionID, semaphore: mediator)
            dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
            dispatch_semaphore_signal(s)
            dispatch_semaphore_wait(mediator, DISPATCH_TIME_FOREVER)
            // got awoken by extract()
            buffer.destroy(1)
            buffer.dealloc(1)
            dispatch_set_context(mediator, nil)
            SemaphorePool.enqueue(mediator)
          }
          OSSpinLockLock(&lock)
          return mediator
        }
        else
        { // try the next enqueued reader instead
          continue
        }
      }
    }
    return nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    if let rs = selection.semaphore
    {
      let buffer = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      buffer.initialize(newElement)
      dispatch_semaphore_signal(rs)
      return true
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(selection)")
    return false
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    OSSpinLockLock(&lock)
    if !readerQueue.isEmpty
    {
      if let s = semaphore.get()
      {
        if let rs = selectPutNow()
        {
          let selection = Selection(id: selectionID, semaphore: rs)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
        }
        OSSpinLockUnlock(&lock)
        dispatch_semaphore_signal(s)
        return {}
      }
      else
      {
        OSSpinLockUnlock(&lock)
        return {}
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if let s = semaphore.get()
      {
        dispatch_semaphore_signal(s)
      }
      return {}
    }

    // enqueue the SemaphoreChan and hope for the best.
    writerQueue.enqueue(.selection(semaphore, selectionID))
    OSSpinLockUnlock(&lock)

    return {}
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let ws = selectGetNow()
    {
      OSSpinLockUnlock(&lock)
      return Selection(id: selectionID, semaphore: ws)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  private func selectGetNow() -> dispatch_semaphore_t?
  {
    precondition(lock != 0, __FUNCTION__)
    while let ssema = writerQueue.dequeue()
    {
      switch ssema
      {
      case .semaphore(let ws):
        return ws

      case .selection(let c, let selectionID):
        if let s = c.get()
        {
          OSSpinLockUnlock(&lock)
          let mediator = SemaphorePool.dequeue()
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          dispatch_set_context(mediator, buffer)
          let selection = Selection(id: selectionID, semaphore: mediator)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
          dispatch_semaphore_wait(mediator, DISPATCH_TIME_FOREVER)
          // got awoken by insert()
          precondition(dispatch_get_context(mediator) == buffer, "Unknown context in \(__FUNCTION__)")

          // two select()s talking to each other need a 3rd thread
          dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
            dispatch_semaphore_wait(mediator, DISPATCH_TIME_FOREVER)
            // got awoken by extract()
            buffer.destroy(1)
            buffer.dealloc(1)
            dispatch_set_context(mediator, nil)
            SemaphorePool.enqueue(mediator)
          }
          OSSpinLockLock(&lock)
          return mediator
        }
        else
        { // try the next enqueued reader instead
          continue
        }
      }
    }
    return nil
  }
  
  override func extract(selection: Selection) -> T?
  {
    if let ws = selection.semaphore
    {
      let element: T = UnsafePointer(dispatch_get_context(ws)).memory
      dispatch_semaphore_signal(ws)
      return element
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(selection)")
    return nil
  }

  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    OSSpinLockLock(&lock)
    if !writerQueue.isEmpty
    {
      if let s = semaphore.get()
      {
        if let ws = selectPutNow()
        {
          let selection = Selection(id: selectionID, semaphore: ws)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
        }
        OSSpinLockUnlock(&lock)
        dispatch_semaphore_signal(s)
        return {}
      }
      else
      {
        OSSpinLockUnlock(&lock)
        return {}
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if let s = semaphore.get()
      {
        dispatch_semaphore_signal(s)
      }
      return {}
    }

    // enqueue the SemaphoreChan and hope for the best.
    readerQueue.enqueue(.selection(semaphore, selectionID))
    OSSpinLockUnlock(&lock)

    return {}
  }
}
