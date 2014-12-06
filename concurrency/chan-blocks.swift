//
//  chan-blocks.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Our basis for channel implementations based on Grand Central Dispatch

  This is an adaptation of a standard pthreads solution for the producer/consumer problem
  to the blocks-and-queues Weltanschauung of Grand Central Dispatch. It might not be optimal.
*/

class gcdChan<T>: Chan<T>
{
  // instance variables

  var closed: Bool = false

  let readers = DispatchQueueWrapper(name: "com.tffenterprises.channelreader")
  let writers = DispatchQueueWrapper(name: "com.tffenterprises.channelwriter")

  // Initialization

  override init()
  {
    super.init()
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

///**
//  The SelectionChannel methods for SelectChan
//*/
//
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
