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
    Factory function to obtain a new, unbuffered `Chan<T>` object (channel capacity = 0),
    wrapped by a `Sender<T>` and `Receiver<T>` pair.

    - returns: newly-created, paired `Sender<T>` and `Receiver<T>`.
  */

  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new `Chan<T>` object,
    wrapped by a `Sender<T>` and `Receiver<T>` pair.

    - parameter capacity: the buffer capacity of the channel. If capacity is 0, an unbuffered channel will be created.
    - returns: newly-created, paired `Sender<T>` and `Receiver<T>`.
  */

  public class func Make(capacity: Int) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Wrap(Chan.Make(capacity))
  }

  public class func Make(_: T.Type, _ capacity: Int = 0) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(capacity)
  }

  /**
    Wrap a `Chan<T>` in a new `Sender<T>` and `Receiver<T>` pair.

    - parameter c: the Chan<T>
    - returns: newly-created, paired `Sender<T>` and `Receiver<T>`.
  */

  public class func Wrap(c: Chan<T>) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }

  /**
    Wrap a `ChannelType` in a new `Sender` and `Receiver` pair.

    - parameter c: the `ChannelType` object
    - returns: newly-created, paired `Sender` and `Receiver`.
  */

  class func Wrap<C: ChannelType where C.Element == T>(c: C) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }
}
