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

      switch dispatch_get_context(rs)
      {
      case nil:
        preconditionFailure(__FUNCTION__)

      case waitSelect:
        let threadLock = SemaphorePool.dequeue()
        dispatch_set_context(threadLock, &newElement)
        dispatch_set_context(rs, UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque()))
        dispatch_semaphore_signal(rs)
        dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

        // got awoken
        let context = dispatch_get_context(threadLock)
        dispatch_set_context(threadLock, nil)
        SemaphorePool.enqueue(threadLock)

        switch context
        {
        case &newElement:
          return true

        case nil:
          return self.put(newElement)

        default:
          preconditionFailure("Unknown context value (\(context)) in waitSelect case of \(__FUNCTION__)")
        }

      case let buffer: // default
        // attach a new copy of our data to the reader's semaphore
        UnsafeMutablePointer<T>(buffer).initialize(newElement)
        dispatch_semaphore_signal(rs)
        return true
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

    if let ws = writerQueue.dequeue()
    { // data is already available
      OSSpinLockUnlock(&lock)

      switch dispatch_get_context(ws)
      {
      case nil:
        preconditionFailure(__FUNCTION__)

      case waitSelect:
        let buffer = UnsafeMutablePointer<T>.alloc(1)
        let threadLock = SemaphorePool.dequeue()
        dispatch_set_context(threadLock, buffer)
        dispatch_set_context(ws, UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque()))
        dispatch_semaphore_signal(ws)
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

        case nil:
          buffer.dealloc(1)
          return self.get()

        default:
          preconditionFailure("Unknown context value (\(context)) in waitSelect case of \(__FUNCTION__)")
        }

      case let context: // default
        // copy data from a pointer to a variable stored "on the stack"
        let element: T = UnsafePointer(context).memory
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
      preconditionFailure("Unknown context value (\(context)) after sleep state in \(__FUNCTION__)")
    }
  }

  // MARK: SelectableChannelType methods

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
        // waitSelect has a significant chance of failure, but the selectPutNow() path should work "all" the time.
        readerQueue.undequeue(rs)

      default:
        OSSpinLockUnlock(&lock)
        return Selection(id: selectionID, semaphore: rs)
      }
    }
    OSSpinLockUnlock(&lock)
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
    let threadLock = SemaphorePool.dequeue()
    var cancelable = false

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      if let rs = self.readerQueue.dequeue()
      {
        switch dispatch_get_context(rs)
        {
        case nil:
          preconditionFailure(__FUNCTION__)

        case waitSelect:
          if let s = semaphore.get()
          {
            OSSpinLockUnlock(&self.lock)
            dispatch_set_context(threadLock, waitSelect)
            dispatch_set_context(rs, UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque()))
            dispatch_semaphore_signal(rs)
            dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

            // got awoken
            switch dispatch_get_context(threadLock)
            {
            case nil:
              // the counterpart selectGet couldn't obtain its own select semaphore.
              dispatch_set_context(s, nil)
              dispatch_semaphore_signal(s)

            case waitSelect:
              // rs's context should now be a pointer to a buffer.
              assert(dispatch_get_context(rs) != waitSelect, __FUNCTION__)
              // pass the rs semaphore on to insert()
              let selection = Selection(id: selectionID, semaphore: rs)
              dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
              dispatch_semaphore_signal(s)

            case let context: // default
              preconditionFailure("Context \(context) is invalid in waitSelect case of \(__FUNCTION__)")
            }
          }
          else
          {
            self.readerQueue.undequeue(rs)
            // The spinlock isn't released between dequeue() and undequeue(),
            // so this is transparent to other threads.
            OSSpinLockUnlock(&self.lock)
          }

        default:
          if let s = semaphore.get()
          { // pass the rs semaphore on to insert()
            OSSpinLockUnlock(&self.lock)
            let selection = Selection(id: selectionID, semaphore: rs)
            dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
            dispatch_semaphore_signal(s)
          }
          else
          {
            self.readerQueue.undequeue(rs)
            // The spinlock isn't released between dequeue() and undequeue(),
            // so this is transparent to other threads.
            OSSpinLockUnlock(&self.lock)
          }
        }

        dispatch_set_context(threadLock, nil)
        SemaphorePool.enqueue(threadLock)
        return
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
      cancelable = true
      OSSpinLockUnlock(&self.lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

      // got awoken
      switch dispatch_get_context(threadLock)
      {
      case nil:
        // thread was awoken by close(): write operation fails
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }

      case cancelSelect:
        // no need to try for the semaphore.
        break

      case let context: // default
        let rs = Unmanaged<dispatch_semaphore_t>.fromOpaque(COpaquePointer(context)).takeRetainedValue()
        if let s = semaphore.get()
        { // pass rs on to insert()
          let selection = Selection(id: selectionID, semaphore: rs)
          dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
          dispatch_semaphore_signal(s)
        }
        else
        { // signal failure to the reader
          dispatch_set_context(rs, nil)
          dispatch_semaphore_signal(rs)
        }
      }

      dispatch_set_context(threadLock, nil)
      SemaphorePool.enqueue(threadLock)
    }

    return {
      OSMemoryBarrier()
      if cancelable
      { // selectPut is probably in its wait state
        OSSpinLockLock(&self.lock)
        if self.writerQueue.remove(threadLock)
        {
          dispatch_set_context(threadLock, cancelSelect)
          dispatch_semaphore_signal(threadLock)
        }
        OSSpinLockUnlock(&self.lock)
      }
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let ws = writerQueue.dequeue()
    {
      switch dispatch_get_context(ws)
      {
      case nil, cancelSelect:
        preconditionFailure("Context is invalid in \(__FUNCTION__)")

      case waitSelect:
        // waitSelect has a significant chance of failure, but the selectGetNow() path should work "all" the time.
        writerQueue.undequeue(ws)

      default:
        OSSpinLockUnlock(&lock)
        return Selection(id: selectionID, semaphore: ws)
      }
    }
    OSSpinLockUnlock(&lock)
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
    let threadLock = SemaphorePool.dequeue()
    var cancelable = false

    dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
      _ in
      OSSpinLockLock(&self.lock)
      if let ws = self.writerQueue.dequeue()
      {
        switch dispatch_get_context(ws)
        {
        case nil:
          preconditionFailure(__FUNCTION__)

        case waitSelect:
          if let s = semaphore.get()
          {
            OSSpinLockUnlock(&self.lock)

            // we're talking to a selectPut(); it needs a semaphore with a buffer attached
            let buffer = UnsafeMutablePointer<T>.alloc(1)
            dispatch_set_context(threadLock, buffer)
            dispatch_set_context(ws, UnsafeMutablePointer<Void>(Unmanaged.passRetained(threadLock).toOpaque()))
            dispatch_semaphore_signal(ws)
            dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

            // got awoken
            switch dispatch_get_context(threadLock)
            {
            case buffer:
              // thread awoken by insert(); buffer is now initialized with a copy of the message data.
              // pass threadLock on to extract(), mimicking a queued put()
              let selection = Selection(id: selectionID, semaphore: threadLock)
              dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
              dispatch_semaphore_signal(s)

              // wait, and then clean up.
              dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
              switch dispatch_get_context(threadLock)
              {
              case buffer, nil: break
              case let context:
                preconditionFailure("Unknown context value (\(context)) in waitSelect case of \(__FUNCTION__)")
              }
              buffer.destroy()
              buffer.dealloc(1)

            case nil:
              // the counterpart selectPut couldn't obtain its own semaphore.
              buffer.dealloc(1)
              dispatch_semaphore_signal(s)

            case let context: // default
              preconditionFailure("Unknown context value (\(context)) in waitSelect case of \(__FUNCTION__)")
            }
          }
          else
          {
            self.writerQueue.undequeue(ws)
            // The spinlock isn't released between dequeue() and undequeue(),
            // so this is transparent to other threads.
            OSSpinLockUnlock(&self.lock)
          }

        default:
          if let s = semaphore.get()
          { // pass ws on to extract()
            OSSpinLockUnlock(&self.lock)
            let selection = Selection(id: selectionID, semaphore: ws)
            dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
            dispatch_semaphore_signal(s)
          }
          else
          {
            self.writerQueue.undequeue(ws)
            // The spinlock isn't released between dequeue() and undequeue(),
            // so this is transparent to other threads.
            OSSpinLockUnlock(&self.lock)
          }
        }

        dispatch_set_context(threadLock, nil)
        SemaphorePool.enqueue(threadLock)
        return
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
      cancelable = true
      OSSpinLockUnlock(&self.lock)
      dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

      // got awoken
      switch dispatch_get_context(threadLock)
      {
      case nil:
        // thread was awoken by close(): no more data on the channel
        if let s = semaphore.get()
        {
          dispatch_set_context(s, nil)
          dispatch_semaphore_signal(s)
        }

      case cancelSelect:
        // no need to try for the semaphore.
        break

      case let context: // default
        let ws = Unmanaged<dispatch_semaphore_t>.fromOpaque(COpaquePointer(context)).takeRetainedValue()
        if let s = semaphore.get()
        {
          switch dispatch_get_context(ws)
          {
          case waitSelect:
            // we're talking to a selectPut(); it needs a semaphore with a buffer attached
            let buffer = UnsafeMutablePointer<T>.alloc(1)
            dispatch_set_context(threadLock, buffer)
            // the thread waiting on ws already has a reference to our threadLock
            dispatch_semaphore_signal(ws)
            dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

            // thread awoken by insert()
            assert(dispatch_get_context(threadLock) == buffer)

            // pass threadLock on to extract(), i.e. mimic a queued put()
            let selection = Selection(id: selectionID, semaphore: threadLock)
            dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
            dispatch_semaphore_signal(s)

            // wait, and then clean up.
            dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)
            switch dispatch_get_context(threadLock)
            {
            case buffer, nil: break
            case let context:
              preconditionFailure("Unknown context value (\(context)) in waitSelect case of \(__FUNCTION__)")
            }
            buffer.destroy()
            buffer.dealloc(1)

          default:
            // the data is attached from a put(); pass it on to extract()
            let selection = Selection(id: selectionID, semaphore: ws)
            dispatch_set_context(s, UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque()))
            dispatch_semaphore_signal(s)
          }
        }
        else
        { // signal failure to the writer
          dispatch_set_context(ws, nil)
          dispatch_semaphore_signal(ws)
        }
      }

      dispatch_set_context(threadLock, nil)
      SemaphorePool.enqueue(threadLock)
    }

    return {
      OSMemoryBarrier()
      if cancelable
      {
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
}

/**
  Useful fake pointers for use with dispatch_set_context()
*/

private let cancelSelect = UnsafeMutablePointer<Void>(bitPattern: 1)
private let waitSelect   = UnsafeMutablePointer<Void>(bitPattern: 3)
