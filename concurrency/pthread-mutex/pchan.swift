//
//  chan-pthreads.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

/**
  The basis for our real mutex-based channels

  This solution adapted from:
  Oracle Multithreaded Programming Guide, "The Producer/Consumer Problem"
  http://docs.oracle.com/cd/E19455-01/806-5257/sync-31/index.html
*/

public class PChan<T>: Chan<T>
{
  // Instance variables

  final var closed = false
  final var blockedReaders = 0
  final var blockedWriters = 0

  // pthreads variables

  final let channelMutex:   UnsafeMutablePointer<pthread_mutex_t>
  final let readCondition:  UnsafeMutablePointer<pthread_cond_t>
  final let writeCondition: UnsafeMutablePointer<pthread_cond_t>

  // Initialization and destruction

  override init()
  {
    channelMutex = UnsafeMutablePointer<pthread_mutex_t>.alloc(1)
    pthread_mutex_init(channelMutex, nil)

    writeCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(writeCondition, nil)

    readCondition = UnsafeMutablePointer<pthread_cond_t>.alloc(1)
    pthread_cond_init(readCondition, nil)

    closed = false
  }

  deinit
  {
    pthread_mutex_destroy(channelMutex)
    channelMutex.dealloc(1)

    pthread_cond_destroy(readCondition)
    readCondition.dealloc(1)

    pthread_cond_destroy(writeCondition)
    writeCondition.dealloc(1)
  }

  // Computed properties

  /**
    Determine whether the channel has been closed
  */

  final override public var isClosed: Bool { return closed }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already
    been closed. The actual reaction shall be implementation-dependent.
  */

  override public func close()
  {
    if closed { return }

    closed = true

    // Unblock the threads waiting on our conditions.
    if blockedReaders > 0 || blockedWriters > 0
    {
      pthread_mutex_lock(channelMutex)
      pthread_cond_signal(writeCondition)
      pthread_cond_signal(readCondition)
      pthread_mutex_unlock(channelMutex)
    }
  }


  /**
    Factory method to make pthreads channels.
  */

  public class func Make(capacity: Int, queue: Bool) -> Chan<T>
  {
    switch capacity
    {
    case let c where c<1:
      return PUnbufferedChan<T>()

    case 1:
      return PBuffered1Chan<T>()

    default:
      if queue { return PBufferedQChan(capacity) }
      return PBufferedAChan<T>(capacity)
    }
  }

  override public class func Make(capacity: Int) -> Chan<T>
  {
    return Make(capacity, queue: false)
  }
}
