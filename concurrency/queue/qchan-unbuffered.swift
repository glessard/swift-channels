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

  private let readerQueue = FastQueue<ChannelSemaphore>()
  private let writerQueue = FastQueue<ChannelSemaphore>()

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
      rs.setState(.Done)
      rs.signal()
    }
    while let ws = writerQueue.dequeue()
    {
      ws.setState(.Done)
      ws.signal()
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
      switch rs.state
      {
      case .Pointer:
        // attach a new copy of our data to the reader's semaphore
        rs.getPointer().initialize(newElement)
        rs.signal()
        return true

      case let status: // default
        preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // make our data available for a reader
    let threadLock = SemaphorePool.Obtain()
    threadLock.setPointer(&newElement)
    writerQueue.enqueue(threadLock)
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
      preconditionFailure("Unexpected Semaphore state \(state) in \(__FUNCTION__)")
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
      switch ws.state
      {
      case .Pointer:
        let element: T = ws.getPointer().memory
        ws.signal()
        return element

      case let status:
        preconditionFailure("Unexpected Semaphore status \(status) in \(__FUNCTION__)")
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
    threadLock.setPointer(buffer)
    readerQueue.enqueue(threadLock)
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
      preconditionFailure("Unknown context value in \(__FUNCTION__)")
    }
  }
}
