//
//  chan-gcd-buffered1.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-01.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A buffered channel.
*/

class gcdBuffered1Chan<T>: gcdChan<T>
{
  private var element: T?

  // housekeeping variables

  private var elementsWritten: Int64 = -1
  private var elementsRead: Int64 = -1

  // Used to elucidate/troubleshoot message arrival order
  // private var readerCount: Int32 = -1

  // Initialization

  override init()
  {
    element = nil
    super.init()
  }

  //  Computed property accessors

  final override var isEmpty: Bool
  {
    return elementsWritten <= elementsRead
  }

  final override var isFull: Bool
  {
    return elementsWritten > elementsRead
  }

  /**
    Append an element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.isClosed { return }

    // syncprint("trying to send: \(newElement)")

    var hasWritten = false
    while !hasWritten
    {
      writers.mutex { // A suspended writer queue will block here.
        if (self.elementsWritten > self.elementsRead) && !self.closed
        { // suspend writers queue when channel is full
          self.writers.suspend()
          self.readers.resume()
          return
        }

        if !self.closed
        {
          self.element = newElement
          OSAtomicIncrement64Barrier(&self.elementsWritten)
        }
        hasWritten = true

        // syncprint("sent \(self.element) as element \(self.elementsWritten)")

        if (self.elementsWritten > self.elementsRead) && !self.closed
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
        if (self.elementsWritten <= self.elementsRead) && !self.closed
        { // suspend while channel is empty
          self.readers.suspend()
          self.writers.resume()
          return
        }

        if self.closed && (self.elementsWritten == self.elementsRead)
        {
          self.element = nil
        }

        oldElement = self.element
        OSAtomicIncrement64Barrier(&self.elementsRead)
        hasRead = true

        // syncprint("reader \(id) received \(oldElement)")

        if (self.elementsWritten <= self.elementsRead) && !self.closed
        { // suspend while channel is empty
          self.readers.suspend()
        }
        self.writers.resume()
      }
    }

    return oldElement
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
