//
//  chan-pthreads.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Darwin

public enum PChanBufferType
{
  case Buffer
  case Array
  case Queue
}

public class PChan<T>
{
  /**
  Factory method to obtain pthreads channels of the desired channel capacity.
  If capacity is 0, then an unbuffered channel will be created.

  :param: capacity   the buffer capacity of the channel.
  :param: bufferType which kind of backing store should the channel use.

  :return: a newly-created, empty Chan<T>
  */

  public class func Make(capacity: Int, bufferType: PChanBufferType = .Buffer) -> Chan<T>
  {
    switch capacity
    {
    case let c where c<1:
      return PUnbufferedChan()

    default:
      if capacity == 1 { return PBuffered1Chan() }
      switch bufferType
      {
      case .Buffer: return PBufferedBChan(capacity)
      case .Array:  return PBufferedAChan(capacity)
      case .Queue:  return PBufferedQChan(capacity)
      }
    }
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

  final var channelMutex =   pthread_mutex_t()
  final var readCondition =  pthread_cond_t()
  final var writeCondition = pthread_cond_t()

  // Initialization and destruction

  override init()
  {
    pthread_mutex_init(&channelMutex, nil)
    pthread_cond_init(&writeCondition, nil)
    pthread_cond_init(&readCondition, nil)

    closed = false
  }

  deinit
  {
    pthread_mutex_destroy(&channelMutex)
    pthread_cond_destroy(&readCondition)
    pthread_cond_destroy(&writeCondition)
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
      pthread_mutex_lock(&channelMutex)
      pthread_cond_signal(&writeCondition)
      pthread_cond_signal(&readCondition)
      pthread_mutex_unlock(&channelMutex)
    }
  }
}
