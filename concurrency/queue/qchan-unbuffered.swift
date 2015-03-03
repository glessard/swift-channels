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

  private let readerQueue = SemaphoreQueue()
  private let writerQueue = SemaphoreQueue()

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
      dispatch_set_context(rs, nil)
      dispatch_semaphore_signal(rs)
    }
    while let ws = writerQueue.dequeue()
    {
      dispatch_set_context(ws, nil)
      dispatch_semaphore_signal(ws)
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

    if let rs = readerQueue.dequeue()
    { // there is already an interested reader
      OSSpinLockUnlock(&lock)

      let context = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      switch context
      {
      case nil:
        preconditionFailure(__FUNCTION__)

      case waitSelect:
        let threadLock = dispatch_semaphore_create(0)!
        dispatch_set_context(threadLock, &newElement)
        let contextptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque())
        dispatch_set_context(rs, contextptr)
        dispatch_semaphore_signal(rs)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

        let context = dispatch_get_context(threadLock)
        switch context
        {
        case &newElement:
          return true

        case nil:
          return self.put(newElement)

        default:
          preconditionFailure("Weird context value (\(context)) in waitSelect case of \(__FUNCTION__)")
        }

      default:
        // attach a new copy of our data to the reader's semaphore
        context.initialize(newElement)
        dispatch_semaphore_signal(rs)
        return true
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // wait for a buffer from a reader
    let threadLock = SemaphorePool.dequeue()
    // attach a pointer to our data on the stack
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
      preconditionFailure("Weird context value in \(__FUNCTION__)")
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

    if let ws = writerQueue.dequeue()
    { // data is already available
      OSSpinLockUnlock(&lock)

      let context = UnsafePointer<T>(dispatch_get_context(ws))
      switch context
      {
      case nil:
        preconditionFailure(__FUNCTION__)

      case UnsafePointer(waitSelect):
        let threadLock = dispatch_semaphore_create(0)!
        let buffer = UnsafeMutablePointer<T>.alloc(1)
        dispatch_set_context(threadLock, buffer)
        let contextptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque())
        dispatch_set_context(ws, contextptr)
        dispatch_semaphore_signal(ws)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

        let context = dispatch_get_context(threadLock)
        switch context
        {
        case buffer:
          let element = buffer.move()
          buffer.dealloc(1)
          return element

        case nil:
          buffer.dealloc(1)
          return self.get()

        default:
          preconditionFailure("Weird context value (\(context)) in waitSelect case of \(__FUNCTION__)")
        }

      default:
        let element = context.memory
        dispatch_semaphore_signal(ws)
        return element
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
      preconditionFailure("Weird context value in \(__FUNCTION__)")
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    if let rs: dispatch_semaphore_t = selection.getData()
    {
      let context = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      context.initialize(newElement)
      dispatch_semaphore_signal(rs)
      return true
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(selection)")
    return false
  }

  override func selectPutNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let rs = readerQueue.dequeue()
    {
      switch dispatch_get_context(rs)
      {
      case nil, cancelSelect:
        preconditionFailure("Context is invalid in \(__FUNCTION__)")

      case waitSelect:
        readerQueue.undequeue(rs)

      default:
        OSSpinLockUnlock(&lock)
        return Selection(selectionID: selectionID, selectionData: rs)
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      if let rs = self.readerQueue.dequeue()
      {
        if let s = semaphore.get()
        {
          OSSpinLockUnlock(&self.lock)

          let context = dispatch_get_context(rs)
          switch context
          {
          case nil:
            preconditionFailure(__FUNCTION__)

          case waitSelect:
            break

          default:
            let selection = Selection(selectionID: selectionID, selectionData: rs)
            let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
            dispatch_set_context(s, selectptr)
            dispatch_semaphore_signal(s)
            return
          }
        }
        else
        {
          self.readerQueue.undequeue(rs)
          // The spinlock stayed locked between dequeue() and undequeue(),
          // so it was transparent to other threads.
          OSSpinLockUnlock(&self.lock)
          return
        }
      }

      if self.closed
      {
        OSSpinLockUnlock(&self.lock)
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }
      }

      dispatch_set_context(threadLock, waitSelect)
      self.writerQueue.enqueue(threadLock)
      OSSpinLockUnlock(&self.lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

      // got awoken
      let context = COpaquePointer(dispatch_get_context(threadLock))

      switch context
      {
      case nil:
        // thread was awoken by close(): write operation fails
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }
        return

      case COpaquePointer(cancelSelect):
        // no need to try for the semaphore.
        break

      default:
        let selectget = Unmanaged<dispatch_semaphore_t>.fromOpaque(context).takeRetainedValue()
        if let s = semaphore.get()
        {
          let selection = Selection(selectionID: selectionID, selectionData: selectget)
          let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
          dispatch_set_context(s, selectptr)
          dispatch_semaphore_signal(s)
        }
        else
        { // signal failure to the reader
          dispatch_set_context(selectget, nil)
          dispatch_semaphore_signal(selectget)
        }
      }
    }

    return {
      OSSpinLockLock(&self.lock)
      if self.writerQueue.remove(threadLock)
      {
        dispatch_set_context(threadLock, cancelSelect)
        dispatch_semaphore_signal(threadLock)
      }
      OSSpinLockUnlock(&self.lock)
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let ws = writerQueue.dequeue()
    {
      let context = UnsafePointer<T>(dispatch_get_context(ws))
      switch context
      {
      case nil, UnsafePointer(cancelSelect):
        preconditionFailure(__FUNCTION__)

      case UnsafePointer(waitSelect):
        writerQueue.undequeue(ws)

      default:
        OSSpinLockUnlock(&lock)
        let element = context.memory
        dispatch_semaphore_signal(ws)
        return Selection(selectionID: selectionID, selectionData: element)
      }
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      if let ws = self.writerQueue.dequeue()
      {
        if let s = semaphore.get()
        {
          OSSpinLockUnlock(&self.lock)
          
          let context = UnsafePointer<T>(dispatch_get_context(ws))
          switch context
          {
          case nil:
            preconditionFailure(__FUNCTION__)

          default:
            let element = context.memory
            dispatch_semaphore_signal(ws)

            let selection = Selection(selectionID: selectionID, selectionData: element)
            let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
            dispatch_set_context(s, selectptr)
            dispatch_semaphore_signal(s)
            return
          }
        }
        else
        {
          self.writerQueue.undequeue(ws)
          // The spinlock stayed locked between dequeue() and undequeue(),
          // so it was transparent to other threads.
          OSSpinLockUnlock(&self.lock)
          return
        }
      }

      if self.closed
      {
        OSSpinLockUnlock(&self.lock)
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }
        return
      }

      dispatch_set_context(threadLock, waitSelect)
      self.readerQueue.enqueue(threadLock)
      OSSpinLockUnlock(&self.lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

      // got awoken
      let context = COpaquePointer(dispatch_get_context(threadLock))

      switch context
      {
      case nil:
        // thread was awoken by close(): no more data on the channel
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }

      case COpaquePointer(cancelSelect):
        // no need to try for the semaphore.
        break

      default:
        let selectput = Unmanaged<dispatch_semaphore_t>.fromOpaque(context).takeRetainedValue()
        if let s = semaphore.get()
        {
          let context = UnsafeMutablePointer<T>(dispatch_get_context(selectput))
          let selection = Selection(selectionID: selectionID, selectionData: context.memory)
          dispatch_semaphore_signal(selectput)

          let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
          dispatch_set_context(s, selectptr)
          dispatch_semaphore_signal(s)
        }
        else
        { // signal failure to the writer
          dispatch_set_context(selectput, nil)
          dispatch_semaphore_signal(selectput)
        }
      }
    }

    return {
      OSSpinLockLock(&self.lock)
      if self.readerQueue.remove(threadLock)
      {
        dispatch_set_context(threadLock, cancelSelect)
        dispatch_semaphore_signal(threadLock)
      }
      OSSpinLockUnlock(&self.lock)
    }
  }
}

/**
  Useful fake pointers for use with dispatch_set_context()
*/

private let cancelSelect = UnsafeMutablePointer<Void>(bitPattern: 1)
private let waitSelect   = UnsafeMutablePointer<Void>(bitPattern: 3)
