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

  private let readerQueue = FastQueue<QueuedSemaphore>()
  private let writerQueue = FastQueue<QueuedSemaphore>()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

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
      case .Pointer:
        reader.sem.setState(.Done)
        reader.sem.signal()

      case .WaitSelect:
        if reader.sem.setState(.Invalidated) { reader.sem.signal() }

      case .Select, .DoubleSelect, .Invalidated, .Done:
        continue

      default:
        assertionFailure("Unexpected case \(reader.sem.state.rawValue) in \(#function)")
      }
    }
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .Pointer:
        writer.sem.setState(.Done)
        writer.sem.signal()

      case .WaitSelect:
        if writer.sem.setState(.Invalidated) { writer.sem.signal() }

      case .Select, .DoubleSelect, .Invalidated, .Done:
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

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    var element = newElement
    OSSpinLockLock(&lock)

    while let reader = readerQueue.dequeue()
    { // there is already an interested reader
      switch reader.sem.state
      {
      case .Pointer:
        OSSpinLockUnlock(&lock)
        // attach a new copy of our data to the reader's semaphore
        UnsafeMutablePointer<T>(reader.sem.pointer).initialize(newElement)
        reader.sem.signal()
        return true

      case .WaitSelect:
        if reader.sem.setState(.DoubleSelect)
        { // pass the data on to an extract()
          OSSpinLockUnlock(&lock)
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          buffer.initialize(newElement)
          // buffer will be cleaned up in the .DoubleSelect case of extract()

          reader.sem.selection = reader.sel.withSemaphore(reader.sem)
          reader.sem.pointer = UnsafeMutablePointer(buffer)
          reader.sem.signal()

          // the data was passed on; we assume it was successful.
          // if not, select_chan() or extract() are likely to complain, or memory will leak.
          return true
        }

      case .Select, .DoubleSelect, .Invalidated, .Done:
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
    threadLock.setState(.Pointer)
    threadLock.setPointer(&element)
    writerQueue.enqueue(QueuedSemaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    switch threadLock.state
    {
    case .Done:
      // thread was awoken by close() and put() has failed
      return false

    case .Pointer:
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
      case .Pointer:
        OSSpinLockUnlock(&lock)
        let element = UnsafeMutablePointer<T>(writer.sem.pointer).memory
        writer.sem.signal()
        return element

      case .WaitSelect:
        if writer.sem.setState(.Select)
        { // get data from an insert()
          OSSpinLockUnlock(&lock)
          let threadLock = ChannelSemaphore()
          let buffer = UnsafeMutablePointer<T>.alloc(1)
          defer { buffer.dealloc(1) }
          threadLock.setState(.Pointer)
          threadLock.pointer = UnsafeMutablePointer(buffer)
          writer.sem.selection = writer.sel.withSemaphore(threadLock)
          writer.sem.signal()
          threadLock.wait()

          // got awoken by insert()
          assert(threadLock.state == .Pointer && threadLock.pointer == UnsafeMutablePointer<Void>(buffer),
                 "Unexpected Semaphore state \(threadLock.state) in \(#function)")

          return buffer.move()
        }

      case .Select, .DoubleSelect, .Invalidated, .Done:
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
    let buffer = UnsafeMutablePointer<T>.alloc(1)
    defer { buffer.dealloc(1) }
    threadLock.setState(.Pointer)
    threadLock.pointer = UnsafeMutablePointer(buffer)
    readerQueue.enqueue(QueuedSemaphore(threadLock))
    OSSpinLockUnlock(&lock)
    threadLock.wait()

    // got awoken
    switch threadLock.state
    {
    case .Done:
      // thread was awoken by close(): no more data on the channel.
      return nil

    case .Pointer where threadLock.pointer == UnsafeMutablePointer<Void>(buffer):
      return buffer.move()

    case let state: // default
      fatalError("Unknown state (\(state)) after wait in \(#function)")
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    if let rs = selection.semaphore
    {
      switch rs.state
      {
      case .Pointer, .DoubleSelect:
        // attach a new copy of our data to the reader's semaphore
        UnsafeMutablePointer<T>(rs.pointer).initialize(newElement)
        rs.signal()
        return true

      default:
        fatalError("Unexpected state (\(rs.state)) in \(#function)")
      }
    }
    assert(false, "Thread left hanging in \(#function), semaphore not found in \(selection)")
    return false
  }

  override func selectPut(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let reader = readerQueue.dequeue()
    {
      switch reader.sem.state
      {
      case .Pointer:
        if select.setState(.Select)
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

      case .WaitSelect:
        if select.setState(.Select)
        {
          OSSpinLockUnlock(&lock)
          if reader.sem.setState(.DoubleSelect)
          {
            reader.sem.selection = reader.sel.withSemaphore(reader.sem)
            reader.sem.setPointer(UnsafeMutablePointer<T>.alloc(1))

            select.selection = selection.withSemaphore(reader.sem)
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
          readerQueue.undequeue(reader)
          OSSpinLockUnlock(&lock)
        }
        return

      case .Select, .DoubleSelect, .Invalidated, .Done:
        continue

      default:
        fatalError("Unexpected state (\(reader.sem.state)) after wait in \(#function)")
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
    writerQueue.enqueue(QueuedSemaphore(select, selection))
    OSSpinLockUnlock(&lock)
  }

  override func extract(selection: Selection) -> T?
  {
    if let ws = selection.semaphore
    {
      switch ws.state
      {
      case .Pointer:
        let element = UnsafeMutablePointer<T>(ws.pointer).memory
        ws.signal()
        return element

      case .DoubleSelect:
        let pointer = UnsafeMutablePointer<T>(ws.pointer)
        let element = pointer.move()
        pointer.dealloc(1)
        ws.pointer = nil
        ws.selection = nil
        ws.setState(.Done)
        return element

      case let state: // default
        fatalError("Unexpected state (\(state)) in \(#function)")
      }
    }
    assert(false, "Thread left hanging in \(#function), semaphore not found in \(selection)")
    return nil
  }

  override func selectGet(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .Pointer:
        if select.setState(.Select)
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

      case .WaitSelect:
        if select.setState(.DoubleSelect)
        {
          OSSpinLockUnlock(&lock)
          if writer.sem.setState(.Select)
          { // prepare select
            select.selection = selection.withSemaphore(select)
            select.setPointer(UnsafeMutablePointer<T>.alloc(1))

            writer.sem.selection = writer.sel.withSemaphore(select)
            writer.sem.signal()
          }
          else
          { // failed to get both semaphores in the right state at the same time
            select.setState(.Done)
            select.signal()
          }
        }
        else
        {
          writerQueue.undequeue(writer)
          OSSpinLockUnlock(&lock)
        }
        return

      case .Select, .DoubleSelect, .Invalidated, .Done:
        continue

      default:
        fatalError("Unexpected state (\(writer.sem.state)) after wait in \(#function)")
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
    readerQueue.enqueue(QueuedSemaphore(select, selection))
    OSSpinLockUnlock(&lock)
  }
}
