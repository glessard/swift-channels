//
//  chan-pthreads.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

public class PChan<T>
{
  /**
  Factory method to obtain pthreads channels of the desired channel capacity.
  If capacity is 0, then an unbuffered channel will be created.

  :param: capacity the buffer capacity of the channel.
  :param: queue    whether a buffered channel should use a queue-based implementation

  :return: a newly-created, empty Chan<T>
  */

  public class func Make(capacity: Int, useQueue: Bool) -> Chan<T>
  {
    switch capacity
    {
    case let c where c<1:
      return PUnbufferedChan()

    default:
      if useQueue      { return PBufferedQChan(capacity) }
      if capacity == 1 { return PBuffered1Chan() }
      return PBufferedAChan(capacity)
    }
  }

  /**
  Factory method to obtain pthreads channels of the desired channel capacity.
  If capacity is 0, then an unbuffered channel will be created.
  Buffered channels will use a buffer-based implementation

  :param: capacity the buffer capacity of the channel.

  :return: a newly-created, empty Chan<T>
  */

  public class func Make(capacity: Int) -> Chan<T>
  {
    return Make(capacity, useQueue: false)
  }
}

/**
  The basis for our real mutex-based channels

  This solution adapted from:
  Oracle Multithreaded Programming Guide, "The Producer/Consumer Problem"
  http://docs.oracle.com/cd/E19455-01/806-5257/sync-31/index.html
*/

class pthreadsChan<T>: Chan<T>
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

  final override var isClosed: Bool { return closed }

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
}
