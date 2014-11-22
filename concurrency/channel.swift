//
//  channel.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2014-08-16.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

/**
  Factory functions to create Sender and Receiver pairs linked by a channel.
*/

public class Channel<T>
{
  /**
    Factory function to obtain a new, unbuffered Chan<T> object (channel capacity = 0).

    :return: a newly-created, empty, unbuffered Chan<T> object.
  */

  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new Chan<T> object.
  
    :param: capacity the buffer capacity of the channel. If capacity is 0, then an unbuffered channel will be created.
  
    :return: a newly-created, empty Chan<T> object.
  */

  public class func Make(capacity: Int) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    var channel: Chan<T>

    switch capacity
    {
      case let c where c < 1:
        channel = UnbufferedChan<T>()
      case 1:
        channel = Buffered1Chan<T>()

      default:
        channel = BufferedQChan<T>(capacity)
    }

    return (ChanSender(channel), ChanReceiver(channel))
  }

  /**
    Factory function to obtain a new Chan<T> object, using a sample element to determine the type.

    :param: type a sample object whose type will be used for the channel's element type. The object is not retained.
    :param: capacity the buffer capacity of the channel. Default is 0, meaning an unbuffered channel.

    :return: a newly-created, empty, Chan<T> object
  */

  public class func Make(#type: T, _ capacity: Int = 0) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(capacity)
  }

  public class func MakeSingleton() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return SingletonChan<T>.Make()
  }

  public class func MakeSingleton(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return MakeSingleton()
  }
}
