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
  private let buffer: UnsafeMutablePointer<T>

  // MARK: private housekeeping

  private let capacity: Int
  private let mask: Int

  private var head = 0
  private var tail = 0

  private var nextput = 0
  private var nextget = 0

  private let readerQueue = FastQueue<QueuedSemaphore>()
  private let writerQueue = FastQueue<QueuedSemaphore>()

  private var lock = OS_SPINLOCK_INIT

  private var closed = false

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
    buffer = UnsafeMutablePointer.alloc(mask+1)

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
      buffer.advancedBy(head&mask).destroy()
      head = head &+ 1
    }
    buffer.dealloc(mask+1)
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
      case .Ready:
        reader.sem.signal()
        break

      case .WaitSelect:
        if reader.sem.setState(.Invalidated) { reader.sem.signal(); break }

      default:
        continue
      }
    }
    while let writer = writerQueue.dequeue()
    {
      switch writer.sem.state
      {
      case .Ready:
        writer.sem.signal()
        break

      case .WaitSelect:
        if writer.sem.setState(.Invalidated) { writer.sem.signal(); break }

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

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T) -> Bool
  {
    if closed { return false }

    OSSpinLockLock(&lock)

    if !closed && (nextput &- head) >= capacity
    {
      let threadLock = SemaphorePool.Obtain()
      do {
        writerQueue.enqueue(QueuedSemaphore(threadLock))
        OSSpinLockUnlock(&lock)
        threadLock.wait()
        OSSpinLockLock(&lock)
      } while !closed && (nextput &- head) >= capacity
      SemaphorePool.Return(threadLock)
    }

    if !closed
    {
      nextput = nextput &+ 1
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail = tail &+ 1

      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .WaitSelect:
          if reader.sem.setState(.Select)
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
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .WaitSelect:
          if writer.sem.setState(.Select)
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
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return false

        case .WaitSelect:
          if reader.sem.setState(.Select)
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
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return false

        case .WaitSelect:
          if writer.sem.setState(.Select)
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

    :return: the oldest element from the channel.
  */

  override func get() -> T?
  {
    if closed && (tail &- head) <= 0 { return nil }

    OSSpinLockLock(&lock)

    if !closed && (tail &- nextget) <= 0
    {
      let threadLock = SemaphorePool.Obtain()
      do {
        readerQueue.enqueue(QueuedSemaphore(threadLock))
        OSSpinLockUnlock(&lock)
        threadLock.wait()
        OSSpinLockLock(&lock)
      } while !closed && (tail &- nextget) <= 0
      SemaphorePool.Return(threadLock)
    }

    if (tail &- nextget) > 0
    {
      nextget = nextget &+ 1
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1

      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .WaitSelect:
          if writer.sem.setState(.Select)
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
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .WaitSelect:
          if reader.sem.setState(.Select)
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
      assert(closed, __FUNCTION__)
      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return nil

        case .WaitSelect:
          if writer.sem.setState(.Select)
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
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return nil

        case .WaitSelect:
          if reader.sem.setState(.Select)
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

  override func selectPutNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    if !closed && (nextput &- head) >= capacity
    {
      nextput = nextput &+ 1
      OSSpinLockUnlock(&lock)
      return selection
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func insert(selection: Selection, newElement: T) -> Bool
  {
    OSSpinLockLock(&lock)
    if !closed && (nextput &- head) >= capacity
    {
      buffer.advancedBy(tail&mask).initialize(newElement)
      tail += 1

      while let reader = readerQueue.dequeue()
      {
        switch reader.sem.state
        {
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .WaitSelect:
          if reader.sem.setState(.Select)
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
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return true

        case .WaitSelect:
          if writer.sem.setState(.Select)
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

  override func selectPut(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if closed
    {
      OSSpinLockUnlock(&lock)
      if select.setState(.Invalidated)
      {
        select.signal()
      }
    }
    else if (nextput &- head) < capacity // not full
    {
      if select.setState(.Select)
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
          case .Ready:
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .WaitSelect:
            if writer.sem.setState(.Select)
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
          case .Ready:
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .WaitSelect:
            if reader.sem.setState(.Select)
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

  override func selectGetNow(selection: Selection) -> Selection?
  {
    OSSpinLockLock(&lock)
    if (tail &- nextget) > 0
    {
      nextget = nextget &+ 1
      OSSpinLockUnlock(&lock)
      return selection
    }
    OSSpinLockUnlock(&lock)
    return nil
  }

  override func extract(selection: Selection) -> T?
  {
    OSSpinLockLock(&lock)
    if (tail &- head) > 0
    {
      let element = buffer.advancedBy(head&mask).move()
      head = head &+ 1

      while let writer = writerQueue.dequeue()
      {
        switch writer.sem.state
        {
        case .Ready:
          writer.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .WaitSelect:
          if writer.sem.setState(.Select)
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
        case .Ready:
          reader.sem.signal()
          OSSpinLockUnlock(&lock)
          return element

        case .WaitSelect:
          if reader.sem.setState(.Select)
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
      assert(closed, __FUNCTION__)
      OSSpinLockUnlock(&lock)
      return nil
    }
  }
  
  override func selectGet(select: ChannelSemaphore, selection: Selection)
  {
    OSSpinLockLock(&lock)
    if (tail &- nextget) > 0
    {
      if select.setState(.Select)
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
          case .Ready:
            reader.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .WaitSelect:
            if reader.sem.setState(.Select)
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
          case .Ready:
            writer.sem.signal()
            OSSpinLockUnlock(&lock)
            return

          case .WaitSelect:
            if writer.sem.setState(.Select)
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
      if select.setState(.Invalidated)
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
