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

  fileprivate let readerQueue = FastQueue<QueuedSemaphore>()
  fileprivate let writerQueue = FastQueue<QueuedSemaphore>()

  fileprivate var lock = OS_SPINLOCK_INIT

  fileprivate var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return writerQueue.isEmpty
  }

  final override var isFull: Bool
  {
    return readerQueue.isEmpty
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

    // Unblock every thread waiting on our conditions.
    while let reader = readerQueue.dequeue()
    {
      switch reader.sem.state
      {
      case .pointer:
        reader.sem.setState(.done)
        reader.sem.signal()

      case .waitSelect:
        if reader.sem.setState(.invalidated) { reader.sem.signal() }

      case .select, .doubleSelect, .invalidated, .done:
        continue

      default:
        assertionFailure("Unexpected case \(reader.sem.state.rawValue) in \(#function)")
      }
    }
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .pointer:
        writer.sem.setState(.done)
        writer.sem.signal()

      case .waitSelect:
        if writer.sem.setState(.invalidated) { writer.sem.signal() }

      case .select, .doubleSelect, .invalidated, .done:
        continue

      default:
        assertionFailure("Unexpected case \(writer.sem.state.rawValue) in \(#function)")
      }
    }
    OSSpinLockUnlock(&lock)
  }


  /**
    Append an element to the channel

    If no reader is waiting, this call will block.
    If the channel has been closed, no action will be taken.

    - parameter element: the new element to be added to the channel.
  */

  @discardableResult
  override func put(_ newElement: T) -> Bool
  {
    if closed { return false }

    var element = newElement
    OSSpinLockLock(&lock)

    while let reader = readerQueue.dequeue()
    { // there is already an interested reader
      switch reader.sem.state
      {
      case .pointer:
        OSSpinLockUnlock(&lock)
        // attach a new copy of our data to the reader's semaphore
        reader.sem.pointer!.assumingMemoryBound(to: T.self).initialize(to: newElement)
        reader.sem.signal()
        return true

      case .waitSelect:
        if reader.sem.setState(.doubleSelect)
        { // pass the data on to an extract()
          OSSpinLockUnlock(&lock)
          let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
          buffer.initialize(to: newElement)
          // buffer will be cleaned up in the .DoubleSelect case of extract()

          reader.sem.selection = reader.sel.withSemaphore(reader.sem)
          reader.sem.pointer = UnsafeMutableRawPointer(buffer)
          reader.sem.signal()

          // the data was passed on; we assume it was successful.
          // if not, select_chan() or extract() are likely to complain, or memory will leak.
          return true
        }

      case .select, .doubleSelect, .invalidated, .done:
        continue

      default:
        fatalError("Unexpected Semaphore state \(reader.sem.state) in \(#function)")
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return false
    }

    // make our data available for a reader
    let threadLock = ChannelSemaphore()
    threadLock.setState(.pointer)
    threadLock.setPointer(&element)
    writerQueue.enqueue(QueuedSemaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    switch threadLock.state
    {
    case .done:
      // thread was awoken by close() and put() has failed
      return false

    case .pointer:
      assert(threadLock.pointer == &element)
      // the message was succesfully passed.
      return threadLock.pointer == &element

    case let state: // default
      fatalError("Unexpected Semaphore state \(state) after wait in \(#function)")
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    - returns: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed { return nil }

    OSSpinLockLock(&lock)

    while let writer = writerQueue.dequeue()
    { // data is already available
      switch writer.sem.state
      {
      case .pointer:
        OSSpinLockUnlock(&lock)
        let element = writer.sem.pointer!.assumingMemoryBound(to: T.self).pointee
        writer.sem.signal()
        return element

      case .waitSelect:
        if writer.sem.setState(.select)
        { // get data from an insert()
          OSSpinLockUnlock(&lock)
          let threadLock = ChannelSemaphore()
          let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
          defer { buffer.deallocate(capacity: 1) }
          threadLock.setState(.pointer)
          threadLock.pointer = UnsafeMutableRawPointer(buffer)
          writer.sem.selection = writer.sel.withSemaphore(threadLock)
          writer.sem.signal()
          threadLock.wait()

          // got awoken by insert()
          assert(threadLock.state == .pointer && threadLock.pointer == UnsafeMutableRawPointer(buffer),
                 "Unexpected Semaphore state \(threadLock.state) in \(#function)")

          return buffer.move()
        }

      case .select, .doubleSelect, .invalidated, .done:
         continue

      default:
        fatalError("Unexpected Semaphore state \(writer.sem.state) in \(#function)")
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      return nil
    }

    // wait for data from a writer
    let threadLock = ChannelSemaphore()
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { buffer.deallocate(capacity: 1) }
    threadLock.setState(.pointer)
    threadLock.pointer = UnsafeMutableRawPointer(buffer)
    readerQueue.enqueue(QueuedSemaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    switch threadLock.state
    {
    case .done:
      // thread was awoken by close(): no more data on the channel.
      return nil

    case .pointer where threadLock.pointer == UnsafeMutableRawPointer(buffer):
      return buffer.move()

    case let state: // default
      fatalError("Unknown state (\(state)) after wait in \(#function)")
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(_ selection: Selection, newElement: T) -> Bool
  {
    if let rs = selection.semaphore
    {
      switch rs.state
      {
      case .pointer, .doubleSelect:
        // attach a new copy of our data to the reader's semaphore
        rs.pointer!.assumingMemoryBound(to: T.self).initialize(to: newElement)
        rs.signal()
        return true

      default:
        fatalError("Unexpected state (\(rs.state)) in \(#function)")
      }
    }
    assert(false, "Thread left hanging in \(#function), semaphore not found in \(selection)")
    return false
  }

  override func selectPut(_ select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let reader = readerQueue.dequeue()
    {
      switch reader.sem.state
      {
      case .pointer:
        if select.setState(.select)
        {
          OSSpinLockUnlock(&lock)
          select.selection = selection.withSemaphore(reader.sem)
          select.signal()
        }
        else
        {
          readerQueue.undequeue(reader)
          OSSpinLockUnlock(&lock)
        }
        return

      case .waitSelect:
        if select.setState(.select)
        {
          OSSpinLockUnlock(&lock)
          if reader.sem.setState(.doubleSelect)
          {
            reader.sem.selection = reader.sel.withSemaphore(reader.sem)
            reader.sem.setPointer(UnsafeMutablePointer<T>.allocate(capacity: 1))

            select.selection = selection.withSemaphore(reader.sem)
            select.signal()
          }
          else
          { // failed to get both semaphores in the appropriate state at the same time
            select.setState(.done)
            select.signal()
          }
        }
        else
        {
          readerQueue.undequeue(reader)
          OSSpinLockUnlock(&lock)
        }
        return

      case .select, .doubleSelect, .invalidated, .done:
        continue

      default:
        fatalError("Unexpected state (\(reader.sem.state)) after wait in \(#function)")
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.invalidated)
      {
        select.signal()
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    writerQueue.enqueue(QueuedSemaphore(select, selection))
    OSSpinLockUnlock(&lock)
  }

  override func extract(_ selection: Selection) -> T?
  {
    if let ws = selection.semaphore
    {
      switch ws.state
      {
      case .pointer:
        let element = ws.pointer!.assumingMemoryBound(to: T.self).pointee
        ws.signal()
        return element

      case .doubleSelect:
        let pointer = ws.pointer!.assumingMemoryBound(to: T.self)
        let element = pointer.move()
        pointer.deallocate(capacity: 1)
        ws.pointer = nil
        ws.selection = nil
        ws.setState(.done)
        return element

      case let state: // default
        fatalError("Unexpected state (\(state)) in \(#function)")
      }
    }
    assert(false, "Thread left hanging in \(#function), semaphore not found in \(selection)")
    return nil
  }

  override func selectGet(_ select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .pointer:
        if select.setState(.select)
        {
          OSSpinLockUnlock(&lock)
          select.selection = selection.withSemaphore(writer.sem)
          select.signal()
        }
        else
        {
          writerQueue.undequeue(writer)
          OSSpinLockUnlock(&lock)
        }
        return

      case .waitSelect:
        if select.setState(.doubleSelect)
        {
          OSSpinLockUnlock(&lock)
          if writer.sem.setState(.select)
          { // prepare select
            select.selection = selection.withSemaphore(select)
            select.setPointer(UnsafeMutablePointer<T>.allocate(capacity: 1))

            writer.sem.selection = writer.sel.withSemaphore(select)
            writer.sem.signal()
          }
          else
          { // failed to get both semaphores in the right state at the same time
            select.setState(.done)
            select.signal()
          }
        }
        else
        {
          writerQueue.undequeue(writer)
          OSSpinLockUnlock(&lock)
        }
        return

      case .select, .doubleSelect, .invalidated, .done:
        continue

      default:
        fatalError("Unexpected state (\(writer.sem.state)) after wait in \(#function)")
      }
    }

    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.invalidated)
      {
        select.signal()
      }
      return
    }

    // enqueue the SemaphoreChan and hope for the best.
    readerQueue.enqueue(QueuedSemaphore(select, selection))
    OSSpinLockUnlock(&lock)
  }
}
