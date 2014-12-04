//
//  chan-gcd-unbuffered.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-02.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  A channel with no backing store.
  Send operations block until a receiver is ready.
  Conversely, receive operations block until a sender is ready.
*/

class gcdUnbufferedChan<T>: gcdChan<T>
{
  private var element: T?
  private var blockedReaders: Int32 = 0
  private var blockedWriters: Int32 = 0

  override init()
  {
    element = nil
  }

  //  final override var capacity: Int  { return 0 }

  /**
    isEmpty is meaningless when capacity equals zero.
    However, receive() is nearly guaranteed to block, so return true.

    :return: true
  */

  final override var isEmpty: Bool { return true }

  /**
    isFull is meaningless when capacity equals zero.
    However, send() is nearly guaranteed to block, so return true.

    :return: true
  */

  final override var isFull: Bool  { return true }

  /**
    Tell whether the channel is ready to transfer data.

    An unbuffered channel should always look empty to an external observer.
    What is relevant internally is whether the data "is ready" to be transferred to a receiver.

    :return: whether the data is ready for a receive operation.
  */

  final var isReady: Bool { return (element != nil) }

  /**
    Write an element to the channel

    If no reader is ready to receive, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  override func put(newElement: T)
  {
    if self.isClosed { return }

    // syncprint("writer \(newElement) is trying to send")

    var hasSent = false
    while !hasSent
    {
      // self.blockedWriters += 1 -- atomically
      OSAtomicIncrement32Barrier(&self.blockedWriters)

      writers.mutex { // A suspended writer queue will block here.
        self.mutex.mutex {
          OSAtomicDecrement32Barrier(&self.blockedWriters)

          self.writers.suspend()
          self.readers.resume()

          if (self.blockedReaders < 1 || self.isReady) && !self.isClosed
          {
            // syncprint("writer \(newElement) thinks there are \(self.blockedReaders) blocked readers")
            return // to the top of the loop and be suspended
          }

          assert(!self.isReady || self.isClosed, "Messed up an unbuffered send")

          self.writeElement(newElement)
          hasSent = true

          // Surely there is a reader waiting
          assert(self.blockedReaders > 0 || self.isClosed, "No receiver available!")

          if self.isClosed { self.writers.resume() }

          // syncprint("writer \(newElement) has successfully sent")
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
    element = newElement
  }

  /**
    Receive an element from the channel.

    If the channel is empty, this call will block until an element is available.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  override func take() -> T?
  {
    // let id = readerCount++
    // syncprint("reader \(id) is trying to receive")

    var oldElement: T?
    var hasRead = false
    while !hasRead
    {
      // self.blockedReaders += 1 -- atomically
      OSAtomicIncrement32Barrier(&self.blockedReaders)

      readers.mutex {        // A suspended reader queue will block here.
        self.mutex.mutex {
          OSAtomicDecrement32Barrier(&self.blockedReaders)

          if !self.isReady && !self.isClosed
          {
            self.readers.suspend()
            self.writers.resume()
            // syncprint("reader \(id) thinks there are \(self.blockedWriters) blocked writers")
            return // to the top of the loop and be suspended
          }

          oldElement = self.readElement()
          hasRead = true

          if !self.closed && self.blockedReaders > 0
          { // If other readers are waiting, wait for next writer.
            self.readers.suspend()
          }
          self.writers.resume()
          // syncprint("reader \(id) received \(oldElement)")
        }
      }
    }

    return oldElement
  }

  /**
    Read an from the channel buffer, specific implementation.
    This is used within receive() ->T?
    By *definition*, this method is called while a mutex is locked.
  */

  private func readElement() ->T?
  {
    if let oldElement = self.element
    {
      self.element = nil
      return oldElement
    }
    return nil
  }

//  /**
//    Take the next element that can be received from self, and send it to the channel passed in as a parameter.
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
//        // self.blockedReaders += 1 -- atomically
//        OSAtomicIncrement32Barrier(&self.blockedReaders)
//
//        self.readerMutex {        // A suspended reader queue will block the thread here.
//          self.channelMutex {
//            OSAtomicDecrement32Barrier(&self.blockedReaders)
//
//            if !self.isReady && !self.isClosed
//            {
//              self.suspend(self.readers) // will also resume writers
//              return // to the top of the loop and be suspended
//            }
//
//            channel.selectMutex {
//              channel.selectSend(Selection(messageID: messageID, messageData: self.readElement()))
//            }
//            hasRead = true
//
//            if self.blockedReaders > 0
//            { // If other readers are waiting, wait for next writer.
//              self.suspend(self.readers)
//            }
//            else if self.blockedWriters == 0 && self.blockedReaders == 0
//            { // If both queues are empty, none should be suspended
//              self.resume(self.writers)
//            }
//          }
//        }
//      }
//    }
//
//    return {
//      self.channelMutex { if self.blockedReaders > 0 { self.resume(self.readers) } }
//    }
//  }
}
