//
//  gcd-channel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Factory functions to create Sender and Receiver pairs linked by a channel.
*/

public class gcdChannel<T>
{
  /**
    Factory function to obtain a new, unbuffered Chan<T> object (channel capacity = 0).

    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whose ElementType is T.
  */

  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new Chan<T> object.
  
    :param: capacity the buffer capacity of the channel. If capacity is 0, then an unbuffered channel will be created.
  
    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whose ElementType is T.
  */

  public class func Make(capacity: Int) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    var channel: Chan<T>

    switch capacity
    {
      case let c where c < 1:
        channel = gcdUnbufferedChan<T>()
      case 1:
        channel = gcdBuffered1Chan<T>()

      default:
        channel = gcdBufferedAChan<T>(capacity)
    }

    return Channel.Wrap(channel)
  }

  /**
    Factory function to obtain a new Chan<T> object, from a type T passed in as a parameter.

    :param: type     the type to be used for the channel's element type.
    :param: capacity the buffer capacity of the channel. Default is 0, meaning an unbuffered channel.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whose ElementType is T.
  */

  public class func Make(#type: T, _ capacity: Int = 0) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(capacity)
  }

  /**
    Factory function to obtain a new, single-message channel.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func MakeSingleton() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Channel.Wrap(gcdSingletonChan<T>())
  }

  /**
    Factory function to obtain a new Chan<T> object, from a type T passed in as a parameter.

    :param: type the type to be used for the channel's element type.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func MakeSingleton(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return MakeSingleton()
  }
}
