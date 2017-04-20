//
//  qchan-buffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-11-19.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel that uses a queue of semaphores for scheduling.
*/

final class QBufferedChan<T>: Chan<T>
{
  fileprivate let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  fileprivate let capacity: Int
  fileprivate let mask: Int

  fileprivate var head = 0
  fileprivate var tail = 0

  fileprivate var nextput = 0
  fileprivate var nextget = 0

  fileprivate let readerQueue = FastQueue<QueuedSemaphore>()
  fileprivate let writerQueue = FastQueue<QueuedSemaphore>()

  fileprivate var lock = OS_SPINLOCK_INIT

  fileprivate var closed = false

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // MARK: init/deinit

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : min(capacity, 32768)

    // find the next higher power of 2
    var v = self.capacity - 1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8

    mask = v // buffer size -1
    buffer = UnsafeMutablePointer.allocate(capacity: mask+1)

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  deinit
  {
    while (tail &- head) > 0
    {
      buffer.advanced(by: head&mask).deinitialize()
      head = head &+ 1
    }
    buffer.deallocate(capacity: mask+1)
  }

  // MARK: ChannelType properties

  final override var isEmpty: Bool
  {
    return (tail &- head) <= 0
  }

  final override var isFull: Bool
  {
    return (tail &- head) >= capacity
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

    // Unblock a waiting thread.
    while let reader = readerQueue.dequeue()
    {
      switch reader.sem.state
      {
      case .ready:
        reader.sem.signal()
        break

      case .waitSelect:
        if reader.sem.setState(.invalidated) { reader.sem.signal(); break }

      default:
        continue
      }
    }
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .ready:
        writer.sem.signal()
        break

      case .waitSelect:
        if writer.sem.setState(.invalidated) { writer.sem.signal(); break }

      default:
        continue
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

  override func put(_ newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    if !closed && (nextput &- head) >= capacity
    {
      let threadLock = ChannelSemaphore()
      repeat {
        writerQueue.enqueue(QueuedSemaphore(threadLock))
        OSSpinLockUnlock(&lock)
        threadLock.wait()
        OSSpinLockLock(&lock)
      } while !closed && (nextput &- head) >= capacity
    }

    if !closed
    {
      nextput = nextput &+ 1
      buffer.advanced(by: tail&mask).initialize(to: newElement)
      tail = tail &+ 1

      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return true
          }

        default:
          continue
        }
      }
      while (nextput &- head) < capacity || closed, let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return true
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return true
    }
    else
    {
      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return false

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return false
          }

        default:
          continue
        }
      }
      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return false

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return false
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return false
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
    if closed && (tail &- head) <= 0 { return nil }

    OSSpinLockLock(&lock)

    if !closed && (tail &- nextget) <= 0
    {
      let threadLock = ChannelSemaphore()
      repeat {
        readerQueue.enqueue(QueuedSemaphore(threadLock))
        OSSpinLockUnlock(&lock)
        threadLock.wait()
        OSSpinLockLock(&lock)
      } while !closed && (tail &- nextget) <= 0
    }

    if (tail &- nextget) > 0
    {
      nextget = nextget &+ 1
      let element = buffer.advanced(by: head&mask).move()
      head = head &+ 1

      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return element
          }

        default:
          continue
        }
      }
      while (tail &- nextget) > 0 || closed, let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return element
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      precondition(closed, #function)
      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return nil

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return nil
          }

        default:
          continue
        }
      }
      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return nil

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return nil
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return nil
    }
  }

  // MARK: SelectableChannelType methods

  override func insert(_ selection: Selection, newElement: T) -> Bool
  {
    OSSpinLockLock(&lock)
    if !closed && (tail &- head) < capacity // not full
    {
      buffer.advanced(by: tail&mask).initialize(to: newElement)
      tail = tail &+ 1

      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return true
          }

        default:
          continue
        }
      }
      while (nextput &- head) < capacity || closed, let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return true
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return true
    }
    else
    {
      OSSpinLockUnlock(&lock)
      return false
    }
  }

  override func selectPut(_ select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.invalidated)
      {
        select.signal()
      }
    }
    else if (nextput &- head) < capacity // not full
    {
      if select.setState(.select)
      {
        nextput = nextput &+ 1
        OSSpinLockUnlock(&lock)
        select.selection = selection
        select.signal()
      }
      else
      {
        while let writer = writerQueue.dequeue()
        {
          switch writer.sem.state
          {
          case .ready:
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .waitSelect:
            if writer.sem.setState(.select)
            {
              nextput = nextput &+ 1
              writer.sem.selection = writer.sel
              writer.sem.signal()
              OSSpinLockUnlock(&lock)
              return
            }

          default:
            continue
          }
        }
        while (tail &- nextget) > 0 || closed, let reader = readerQueue.dequeue()
        {
          switch reader.sem.state
          {
          case .ready:
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .waitSelect:
            if reader.sem.setState(.select)
            {
              nextget = nextget &+ 1
              reader.sem.selection = reader.sel
              reader.sem.signal()
              OSSpinLockUnlock(&lock)
              return
            }

          default:
            continue
          }
        }
        OSSpinLockUnlock(&lock)
      }
    }
    else
    {
      writerQueue.enqueue(QueuedSemaphore(select, selection))
      OSSpinLockUnlock(&lock)
    }
  }

  override func extract(_ selection: Selection) -> T?
  {
    OSSpinLockLock(&lock)
    if (tail &- head) > 0
    {
      let element = buffer.advanced(by: head&mask).move()
      head = head &+ 1

      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .waitSelect:
          if writer.sem.setState(.select)
          {
            nextput = nextput &+ 1
            writer.sem.selection = writer.sel
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return element
          }

        default:
          continue
        }
      }
      while (tail &- nextget) > 0 || closed, let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .waitSelect:
          if reader.sem.setState(.select)
          {
            nextget = nextget &+ 1
            reader.sem.selection = reader.sel
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return element
          }

        default:
          continue
        }
      }
      OSSpinLockUnlock(&lock)
      return element
    }
    else
    {
      precondition(closed, #function)
      OSSpinLockUnlock(&lock)
      return nil
    }
  }
  
  override func selectGet(_ select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if (tail &- nextget) > 0
    {
      if select.setState(.select)
      {
        nextget = nextget &+ 1
        OSSpinLockUnlock(&lock)
        select.selection = selection
        select.signal()
      }
      else
      {
        while let reader = readerQueue.dequeue()
        {
          switch reader.sem.state
          {
          case .ready:
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .waitSelect:
            if reader.sem.setState(.select)
            {
              nextget = nextget &+ 1
              reader.sem.selection = reader.sel
              reader.sem.signal()
              OSSpinLockUnlock(&lock)
              return
            }

          default:
            continue
          }
        }
        while (nextput &- head) < capacity || closed, let writer = writerQueue.dequeue()
        {
          switch writer.sem.state
          {
          case .ready:
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .waitSelect:
            if writer.sem.setState(.select)
            {
              nextput = nextput &+ 1
              writer.sem.selection = writer.sel
              writer.sem.signal()
              OSSpinLockUnlock(&lock)
              return
            }

          default:
            continue
          }
        }
        OSSpinLockUnlock(&lock)
      }
    }
    else if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.invalidated)
      {
        select.signal()
      }
    }
    else
    {
      readerQueue.enqueue(QueuedSemaphore(select, selection))
      OSSpinLockUnlock(&lock)
    }
  }
}
