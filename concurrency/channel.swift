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

    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whole ElementType is T.
  */

  public class func Make() -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return Make(0)
  }

  /**
    Factory function to obtain a new Chan<T> object.
  
    :param: capacity the buffer capacity of the channel. If capacity is 0, then an unbuffered channel will be created.
  
    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whole ElementType is T.
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

    return Wrap(channel)
  }

  /**
    Factory function to obtain a new Chan<T> object, using a sample element to determine the type.

    :param: type a sample object whose type will be used for the channel's element type. The object is not retained.
    :param: capacity the buffer capacity of the channel. Default is 0, meaning an unbuffered channel.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair. It wraps one ChannelType implementor whole ElementType is T.
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
    return SingletonChan<T>.Make()
  }

  /**
    Factory function to obtain a new Chan<T> object, using a sample element to determine the type.

    :param: type a sample object whose type will be used for the channel's element type. The object is not retained.

    :return: a newly-created, empty Sender<T>/Receiver<T> pair.
  */

  public class func MakeSingleton(#type: T) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return MakeSingleton()
  }

  class func Wrap(c: Chan<T>) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }

  class func Wrap<T, C: ChannelType where C.ElementType == T>(c: C) -> (tx: Sender<T>, rx: Receiver<T>)
  {
    return (Sender.Wrap(c), Receiver.Wrap(c))
  }
}

/**
  ChannelType is the connection between a SenderType and  ReceiverType.
*/

public protocol ChannelType: BasicChannelType
{
  typealias ElementType

  /**
    Determine whether the channel is empty (and can't be received from at the moment)
  */

  var isEmpty: Bool { get }

  /**
    Determine whether the channel is full (and can't be written to at the moment)
  */

  var isFull: Bool { get }

  /**
    Determine whether the channel has been closed
  */

  var isClosed: Bool { get }

  /**
    Close the channel

    Any items still in the channel remain and can be retrieved.
    New items cannot be added to a closed channel.

    It could be considered an error to close a channel that has already been closed.
    The actual reaction shall be implementation-dependent.
  */

  func close()

  /**
    Send a new element to the channel

    If the channel is full, this call will block.
    If the channel has been closed, no action will be taken.

    :param: element the new element to be added to the channel.
  */

  func put(newElement: ElementType)

  /**
    Receive the oldest element from the channel.

    If the channel is empty, this call will block.
    If the channel is empty and closed, this will return nil.

    :return: the oldest element from the channel.
  */

  func take() -> ElementType?
}
