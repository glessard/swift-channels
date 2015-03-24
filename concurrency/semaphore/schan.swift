//
//  schan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-14.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

public class SChan<T>
{
  /**
    Factory method to obtain semaphore-based channels of the desired channel capacity.
    If capacity is less than 1, then an 1-element channel will be created.
    (The solution cannot work with no buffer.)
  
    These channels are build around a solution adapted from:
    Oracle Multithreaded Programming Guide, Chapter 4, section 5: "Semaphores"
    http://docs.oracle.com/cd/E19455-01/806-5257/6je9h032s/index.html

    :param: capacity   the buffer capacity of the channel.

    :return: a newly-created, empty Chan<T>
  */

  public class func Make(capacity: Int) -> Chan<T>
  {
    // Note that an SBufferedChan with a capacity of 0 *will* deadlock.
    return SBufferedChan<T>((capacity < 1) ? 1 : capacity)
  }

  /**
    Factory method to obtain a (buffered) single-message channel.

    :return: a newly-created, empty Chan<T>
  */

  public class func MakeSingleton() -> Chan<T>
  {
    return SingletonChan()
  }

  public class func MakeSingleton(element: T) -> Chan<T>
  {
    return SingletonChan(element)
  }
}
