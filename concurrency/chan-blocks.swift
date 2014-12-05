//
//  chan-blocks.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Foundation
import Dispatch

/**
  Housekeeping help for dispatch_queue_t objects.
  For some reason they don't expose their state at all,
  so we have to do some of it ourselves.
*/

private let Running:   Int32 = 0
private let Suspended: Int32 = 1
private let Transient: Int32 = -1

final class QueueWrapper
{
  private let queue: dispatch_queue_t
  private var state: Int32 = Running

  init(name: String)
  {
    queue = dispatch_queue_create(name+String(arc4random()), DISPATCH_QUEUE_SERIAL)
  }

  deinit
  {
    // If we get here with a suspended queue, GCD will trigger a crash.
    resume()
  }

  /**
    Is the queue running?
  */

  final var isRunning: Bool { return (state == Running) }

  /**
    Suspend the queue if it is running
  */

  final func suspend()
  {
    if OSAtomicCompareAndSwap32Barrier(Running, Transient, &state)
    {
      dispatch_suspend(queue)
      state = Suspended
    }
  }

  /**
    Resume the queue if it is suspended

    Somehow, despite the (conceptually) bulletproof housekeeping, the embedded call to
    dispatch_resume() sometimes crashes when used by gcdUnbufferedChan<T>. Mysterious.
  */

  final func resume()
  {
    if OSAtomicCompareAndSwap32Barrier(Suspended, Transient, &state)
    {
      dispatch_resume(queue)
      state = Running
    }
  }

  /**
    Synchronously dispatch a block to the queue
  */

  final func mutex(task: () -> ())
  {
    dispatch_sync(queue) { task() }
  }

  /**
    Asynchronously dispatch a block to the queue
  */

  final func async(task: () -> ())
  {
    dispatch_async(queue) { task() }
  }
}

/**
  Our basis for channel implementations based on Grand Central Dispatch

  This is an adaptation of a standard pthreads solution for the producer/consumer problem
  to the blocks-and-queues Weltanschauung of Grand Central Dispatch. It might not be optimal.
*/

class gcdChan<T>: Chan<T>
{
  // instance variables

  var closed: Bool = false

  let mutex:   QueueWrapper
  let readers: QueueWrapper
  let writers: QueueWrapper

  // Initialization

  override init()
  {
    mutex   = QueueWrapper(name: "channelmutex")
    readers = QueueWrapper(name: "com.tffenterprises.channelreader")
    writers = QueueWrapper(name: "com.tffenterprises.channelwriter")
  }

  // Computed properties

  /**
    Determine whether the channel has been closed
  */

  final override var isClosed: Bool { return closed }
  
  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It should perhaps be considered an error to close a channel that has
    already been closed, but in fact nothing will happen if it were to occur.
  */

  override func close()
  {
    if closed { return }

    // syncprint("closing channel")

    closed = true
    readers.resume()
    writers.resume()
  }
}

/**
  A buffered channel.
*/

class gcdBufferedChan<T>: gcdChan<T>
{
  /**
    Append an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.isClosed { return }

//    syncprint("trying to send: \(newElement)")

    var hasSent = false
    while !hasSent
    {
      writers.mutex { // A suspended writer queue will block here.
        self.mutex.mutex {
          if self.isFull && !self.isClosed
          {
            self.writers.suspend()
            return // to the top of the while loop and be suspended
          }

          // If Channel is closed, we could get here
          // while the queue is "full". Don't overflow.
          if !self.isFull { self.writeElement(newElement) }
          hasSent = true

//          syncprint("sent element: \(newElement)")

          if self.isFull && !self.isClosed
          { // Preemptively suspend writers queue when channel is full
            self.writers.suspend()
          }
          else
          { // Channel is not empty; resume the readers queue.
            self.readers.resume()
          }
        }
      }
    }
  }

  /**
    Write an element to the channel buffer, specific implementation.
    This is used within send(newElement: T).
    By *definition*, this method is called while a mutex is locked.
  */
  private func writeElement(newElement: T)
  {
    _ = newElement
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func take() -> T?
  {
//    let id = readerCount++
//    syncprint("trying to receive #\(id)")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      readers.mutex { // A suspended reader queue will block here.
        self.mutex.mutex {
          if self.isEmpty && !self.isClosed
          {
            self.readers.suspend()
            return // to the top of the while loop and be suspended
          }

          oldElement = self.readElement()
          hasRead = true

//          syncprint("reader \(id) received \(oldElement)")

          if self.isEmpty && !self.isClosed
          { // Preemptively suspend readers on empty channel
            self.readers.suspend()
          }
          else
          { // Channel is not full; resume the writers queue.
            self.writers.resume()
          }
        }
      }
    }

    assert(oldElement != nil || self.isClosed)

    return oldElement
  }

  /**
    Read an from the channel buffer, specific implementation.
    This is used within receive() ->T?
    By *definition*, this method is called while a mutex is locked.
  */
  private func readElement() ->T?
  {
    return nil
  }

  /**
    Take the next element that can be received from self,
    and send it to the channel passed in as a parameter.

    :param: channel   the channel to which we're re-sending the element.
    :param: messageID an identifier to be sent as the return notification.

    :return: a closure that will unblock the thread if needed.
  */

//  override func selectReceive(channel: SelectChan<SelectionType>, messageID: Selectable) -> Signal
//  {
//    async {
//      var hasRead = false
//      while !hasRead
//      {
//        self.readerMutex { // A suspended reader queue will block here.
//          self.channelMutex {
//            if self.isEmpty && !self.isClosed && !channel.isClosed
//            {
//              self.suspend(self.readers)
//              return // to the top of the while loop and be suspended
//            }
//
//            channel.selectMutex {
//              channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//            }
//            hasRead = true
//
//            if self.isEmpty && !self.isClosed
//            { // Preemptively suspend readers when channel is empty
//              self.suspend(self.readers)
//            }
//            else
//            { // Channel is not full; resume the writers queue.
//              self.resume(self.writers)
//            }
//          }
//        }
//      }
//    }
//    
//    return { self.channelMutex { self.resume(self.readers) } }
//  }
}


/**
  A buffered channel with an N>1 element queue
*/

class gcdBufferedQChan<T>: gcdBufferedChan<T>
{
  private let count: Int
  private var q: Queue<T>

  init(var _ capacity: Int)
  {
    count = (capacity < 1) ? 1: capacity
    self.q = Queue<T>()
  }

  convenience override init()
  {
    self.init(1)
  }

//  override func capacityFunc() -> Int { return count }

  final override var isEmpty: Bool { return q.isEmpty }

  final override var isFull:  Bool { return q.count >= count }

  private override func writeElement(newElement: T)
  {
    q.enqueue(newElement)
  }

  private override func readElement() ->T?
  {
    return q.dequeue()
  }
}

/**
  A buffered channel with a one-element backing store.
*/

//class gcdBuffered1Chan<T>: gcdBufferedChan<T>
//{
//  private var element: T?
//
//  override init()
//  {
//    element = nil
//  }
//
////  override func capacityFunc() -> Int { return 1 }
//
//  final override var isEmpty: Bool { return (element == nil) }
//
//  final override var isFull: Bool  { return (element != nil) }
//
//  private override func writeElement(newElement: T)
//  {
//    element = newElement
//  }
//
//  private override func readElement() ->T?
//  {
//    if let oldElement = self.element
//    {
//      self.element = nil
//      return oldElement
//    }
//    return nil
//  }
//}

/**
  The SelectionChannel methods for SelectChan
*/

//extension SelectChan //: SelectingChannel
//{
//  /**
//    selectMutex() must be used to send data to a SelectingChannel in a thread-safe manner
//
//    Actions which must be performed synchronously with the SelectChan should be passed to
//    selectMutex() as a closure. The closure will only be executed if the channel is still open.
//  */
//
//  public func selectMutex(action: () -> ())
//  {
//    if !self.isClosed
//    {
//      channelMutex { action() }
//    }
//  }
//
//  /**
//    selectSend() will send data to a SelectingChannel.
//    It must be called within the closure sent to selectMutex() for thread safety.
//    By definition, this call occurs while this channel's mutex is locked for the current thread.
//  */
//
//  public func selectSend(newElement: T)
//  {
//    super.writeElement(newElement)
//    self.resume(self.readers)
//  }
//}

// Used to elucidate/troubleshoot message arrival order
//private var readerCount = 0
