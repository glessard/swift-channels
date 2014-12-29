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
    Factory function to obtain a new, unbuffered Chan<T> object (channel capacity = 0),
    wrapped by a Sender<T>/Receiver<T> pair.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new Chan<T> object, wrapped by a Sender<T>/Receiver<T> pair.

    :param: capacity the buffer capacity of the channel. If capacity is 0, an unbuffered channel will be created.
  
    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func Make(capacity: Int) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Wrap(Chan<T>.Make(capacity))
  }

  /**
    Factory function to obtain a new Chan<T> object, wrapped by a Sender<T>/Receiver<T> pair.

    :param: type a sample variable whose type will be used for the channel's element type. The variable is not used.
    :param: capacity the buffer capacity of the channel. The default is 0 for an unbuffered channel.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func Make(#type: T, _ capacity: Int = 0) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(capacity)
  }

  public class func Make(_: T.Type, _ capacity: Int = 0) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(capacity)
  }

  /**
    Factory function to obtain a single-message channel, wrapped by a Sender<T>/Receiver<T> pair.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func MakeSingleton() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Wrap(SingletonChan<T>())
  }

  /**
    Factory function to obtain a single-message channel, wrapped by a Sender<T>/Receiver<T> pair.

    :param: type a sample variable whose type will be used for the channel's element type. The variable is not used.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func MakeSingleton(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return MakeSingleton()
  }

  /**
    Wrap a Chan<T> in a Sender<T>/Receiver<T> pair.

    :param:  c the Chan<T>

    :return: a new Sender<T>/Receiver<T> pair.
  */

  class func Wrap(c: Chan<T>) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }

  /**
    Wrap a ChannelType in a Sender/Receiver pair.

    :param:  c the ChannelType object

    :return: a new Sender/Receiver pair.
  */

  class func Wrap<C: ChannelType where C.Element == T>(c: C) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }
}
