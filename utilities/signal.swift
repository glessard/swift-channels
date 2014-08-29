//
//  signal.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

import Dispatch

public class Signal
{
  public func Raise()
  {
  }
}

public class pthreadSignal: Signal
{
  // These are references whose memory will be taken care of elsewhere.
  private var threadMutex:     UnsafeMutablePointer<pthread_mutex_t>
  private var threadCondition: UnsafeMutablePointer<pthread_cond_t>

  public init(cond: UnsafeMutablePointer<pthread_cond_t>, mutex: UnsafeMutablePointer<pthread_mutex_t>)
  {
    threadCondition = cond
    threadMutex = mutex
  }

  public override func Raise()
  {
    pthread_mutex_lock(threadMutex)
    pthread_cond_broadcast(threadCondition)
    pthread_mutex_unlock(threadMutex)
  }
}
