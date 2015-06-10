//
//  qchan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-14.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

public class QChan<T>
{
  /**
    Factory method to obtain queue-based channels of the desired channel capacity.
    If capacity is 0, then an unbuffered channel will be created.

    - parameter capacity:   the buffer capacity of the channel.

    - returns: a newly-created, empty Chan<T>
  */

  public class func Make(capacity: Int) -> Chan<T>
  {
    switch capacity < 1
    {
    case true:
      return QUnbufferedChan()

    default:
      return QBufferedChan(capacity)
    }
  }
}
