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
  // housekeeping variables

  private let readerQueue = SemaphoreQueue()
  private let writerQueue = SemaphoreQueue()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Computed property accessors

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

      // attach a new copy of our data to the reader's semaphore
      let pointer = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      if pointer == nil
      { // not a normal code path.
        precondition(false, __FUNCTION__)
        return false
      }

      pointer.initialize(newElement)
      dispatch_semaphore_signal(rs)
      return true
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    let threadLock = SemaphorePool.dequeue()
    // attach a pointer to our data on the stack
    dispatch_set_context(threadLock, &newElement)
    writerQueue.enqueue(threadLock)
    OSSpinLockUnlock(&lock)
    dispatch_semaphore_wait(threadLock, DISPATCH_TIME_FOREVER)

    // got awoken
    let context = UnsafePointer<T>(dispatch_get_context(threadLock))
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)

    switch context
    {
    case nil:
      // thread was awoken by close() and put() has failed
      return false

    default:
      assert(context == &newElement)
      return true
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
      if context == nil
      { // not a normal code path.
        precondition(false, __FUNCTION__)
        return nil
      }
      let element = context.memory
      dispatch_set_context(ws, nil)
      dispatch_semaphore_signal(ws)
      return element
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
    let context = UnsafeMutablePointer<T>(dispatch_get_context(threadLock))
    dispatch_set_context(threadLock, nil)
    SemaphorePool.enqueue(threadLock)

    switch context
    {
    case nil:
      // thread was awoken by close(): no more data on the channel.
      buffer.dealloc(1)
      return nil

    default:
      assert(context == buffer)
      let element = buffer.move()
      buffer.dealloc(1)
      return element
    }
  }

  override func selectPutNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let rs = readerQueue.dequeue()
    {
      OSSpinLockUnlock(&lock)
      return Selection(selectionID: selectionID, selectionData: rs)
    }
    else
    {
      OSSpinLockUnlock(&lock)
      return nil
    }
  }

  override func insert(ref: Selection, item: T) -> Bool
  {
    if let rs: dispatch_semaphore_t = ref.getData()
    {
      let pointer = UnsafeMutablePointer<T>(dispatch_get_context(rs))
      if pointer == nil
      { // not a normal code path.
        assert(false, __FUNCTION__)
        return false
      }

      pointer.initialize(item)
      dispatch_semaphore_signal(rs)
      return true
    }
    assert(false, "Thread left hanging in \(__FUNCTION__), semaphore not found in \(ref)")
    return false
  }

  override func selectPut(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      while !self.closed
      {
        if let rs = self.readerQueue.dequeue()
        {
          if let s = semaphore.get()
          {
            OSSpinLockUnlock(&self.lock)

            let selection = Selection(selectionID: selectionID, selectionData: rs)
            let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
            dispatch_set_context(s, selectptr)
            dispatch_semaphore_signal(s)
            return
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

        OSSpinLockUnlock(&self.lock)

        // A weak-sauce busy-wait solution.
        // This is not a good solution, though it works
        // (note that it will pretty much lose any race against a QBufferedChan).
        // An ideal solution would require waiting for the other 2 threads at once
        // (the thread that runs get() and the thread that runs select()).
        // This would mean having a local semaphore, enqueue it to the writerQueue,
        // and wait for a reader. Even if the issue of reliably aborting the message reception is
        // solved, the writer needs to handle the case of a message that fails to get passed
        // on to select() (if the selectPut thread loses its race to obtain the semaphore after having
        // gotten the semaphore from a get() thread).
        // The busy-wait is a way to defer a solution to these issues until a later time.

        dispatch_semaphore_wait(threadLock, dispatch_time(DISPATCH_TIME_NOW, 10_000))
        if dispatch_get_context(threadLock) == abortSelect
        {
          return
        }

        OSSpinLockLock(&self.lock)
      }

      OSSpinLockUnlock(&self.lock)

      // channel is closed; try to wake select() with a nil message
      if let s = semaphore.get()
      {
        dispatch_set_context(s, nil)
        dispatch_semaphore_signal(s)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
    }
  }

  override func selectGetNow(selectionID: Selectable) -> Selection?
  {
    OSSpinLockLock(&lock)
    if let ws = writerQueue.dequeue()
    {
      OSSpinLockUnlock(&lock)

      let context = UnsafePointer<T>(dispatch_get_context(ws))
      if context == nil
      { // not a normal code path.
        assert(false, __FUNCTION__)
        // dispatch_semaphore_signal(nil)
        return nil
      }
      let element = context.memory
      dispatch_set_context(ws, nil)
      dispatch_semaphore_signal(ws)

      return Selection(selectionID: selectionID, selectionData: element)
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func selectGet(semaphore: SemaphoreChan, selectionID: Selectable) -> Signal
  {
    let threadLock = dispatch_semaphore_create(0)!

    async {
      OSSpinLockLock(&self.lock)

      while !self.closed
      {
        if let ws = self.writerQueue.dequeue()
        {
          if let s = semaphore.get()
          {
            OSSpinLockUnlock(&self.lock)
            
            let context = UnsafePointer<T>(dispatch_get_context(ws))
            if context == nil
            { // not a normal code path.
              assert(false, __FUNCTION__)
              // dispatch_semaphore_signal(nil)
              return
            }
            let element = context.memory
            dispatch_set_context(ws, nil)
            dispatch_semaphore_signal(ws)

            let selection = Selection(selectionID: selectionID, selectionData: element)
            let selectptr = UnsafeMutablePointer<Void>(Unmanaged.passRetained(selection).toOpaque())
            dispatch_set_context(s, selectptr)
            dispatch_semaphore_signal(s)
            return
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

        OSSpinLockUnlock(&self.lock)

        // A weak-sauce busy-wait solution.
        // This is not a good solution, though it works
        // (note that it will pretty much lose any race against a QBufferedChan).
        // An ideal solution would require waiting for the other 2 threads at once
        // (the thread that runs put() and the thread that runs select()).
        // This would mean having a local semaphore, enqueue it to the readerQueue,
        // and wait for a writer. Even if the issue of reliably aborting the message reception is
        // solved, the writer needs to handle the case of a message that fails to get passed
        // on to select() (if the selectGet thread loses its race to obtain the semaphore after having
        // gotten data from a put() thread).
        // The busy-wait is a way to defer a solution to these issues until a later time.

        dispatch_semaphore_wait(threadLock, dispatch_time(DISPATCH_TIME_NOW, 10_000))
        if dispatch_get_context(threadLock) == abortSelect
        {
          return
        }

        OSSpinLockLock(&self.lock)
      }

      OSSpinLockUnlock(&self.lock)

      // channel is closed; try to wake select() with a nil message.
      if let s = semaphore.get()
      {
        dispatch_set_context(s, nil)
        dispatch_semaphore_signal(s)
      }
    }

    return {
      dispatch_set_context(threadLock, abortSelect)
      dispatch_semaphore_signal(threadLock)
    }
  }
}
