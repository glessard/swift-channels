//
//  chan-gcd-bufferedN-ringbuffer.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-01.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A buffered channel.
*/

final class gcdBufferedAChan<T>: gcdChan<T>
{
  private final let capacity: Int

  private final var buffer: Array<T?>
  private final let buflen: Int

  // housekeeping variables

  private var elementsWritten: Int64 = 0
  private var elementsRead: Int64 = 0

  private var head = 0
  private var tail = 0

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Initialization

  init(_ capacity: Int)
  {
    self.capacity = (capacity < 1) ? 1 : capacity

    buflen = capacity // a potential performance improvement may exist if this were a power of 2
    buffer = Array<T?>(count: buflen, repeatedValue: nil)

    super.init()
  }

  convenience override init()
  {
    self.init(1)
  }

  //  Computed property accessors

  final override var isEmpty: Bool
  {
    return elementsRead >= elementsWritten
  }

  final override var isFull: Bool
  {
    return elementsRead+capacity <= elementsWritten
  }

  /**
    Append an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.closed { return }

    // syncprint("trying to send: \(newElement)")

    var hasSent = false
    while !hasSent
    {
      writers.mutex { // A suspended writer queue will block here.

        if !self.closed && self.elementsWritten >= (self.elementsRead + self.capacity)
        { // suspend writers queue when channel is full
          self.writers.suspend()
          self.readers.resume()
          return
        }

        if !self.closed
        {
          self.buffer[self.tail%self.buflen] = newElement
          self.tail += 1
          OSAtomicIncrement64Barrier(&self.elementsWritten)
          // syncprint("sent \(self.element) as element \(self.elementsWritten)")
        }
        hasSent = true

        if !self.closed && self.elementsWritten >= (self.elementsRead + self.capacity)
        { // suspend writers queue when channel is full
          self.writers.suspend()
        }
        self.readers.resume()
      }
    }
  }

  /**
    Return the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func take() -> T?
  {
    // let id = OSAtomicIncrement32Barrier(&readerCount)
    // syncprint("trying to receive #\(id)")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      readers.mutex { // A suspended reader queue will block here.

        if !self.closed && (self.elementsWritten <= self.elementsRead)
        { // suspend while channel is empty
          self.readers.suspend()
          self.writers.resume()
          return
        }

        if self.closed && (self.elementsWritten <= self.elementsRead)
        {
          oldElement = nil
        }
        else
        {
          oldElement = self.buffer[self.head%self.buflen]
          self.head += 1
          OSAtomicIncrement64Barrier(&self.elementsRead)
        }
        hasRead = true

        // syncprint("reader \(id) received \(oldElement)")

//        if (self.elementsWritten == self.elementsRead)
//        {
//          self.cleanup()
//        }

        if !self.closed && (self.elementsWritten <= self.elementsRead)
        { // suspend while channel is empty
          self.readers.suspend()
        }
        self.writers.resume()
      }
    }

    return oldElement
  }

  private final func cleanup()
  {
    writers.async { [weak self] in
      // True things during this block:
      // 1. elementsWritten and tail won't change
      // 2. elementsRead and head could
      // 3. All 4 variables might be different than when the block was enqueued.

      if let c = self
      {
        let head = c.head
        for i in reverse(0..<c.buflen)
        {
          let index = (head+i)%c.buflen
//          if index < (c.tail%c.buflen)
//          {
//            c.buffer[index] = nil
//          }
        }
      }
    }
  }

//  /**
//    Take the next element that can be received from self,
//    and send it to the channel passed in as a parameter.
//
//    :param: channel   the channel to which we're re-sending the element.
//    :param: messageID an identifier to be sent as the return notification.
//
//    :return: a closure that will unblock the thread if needed.
//  */
//
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
