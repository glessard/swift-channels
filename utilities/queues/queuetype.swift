//
//  queuetype.swift
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-30.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

// MARK: protocol QueueType

protocol QueueType
{
  typealias Element

  /**
    Initialize an empty queue
  */

  init()

  /**
    Initialize a queue with an initial element
  
    - parameter newElement: the initial element of the new queue
  */

  init(_ newElement: Element)

  /**
    Return whether the queue is empty
    For some implementations, it might be faster to check for queue emptiness
    rather than attempting a dequeue on an empty queue.
  */

  var isEmpty: Bool { get }

  /**
    Add a new element to the queue.
  
    - parameter newElement: a new element
  */

  func enqueue(newElement: Element)

  /**
    Return the oldest element from the queue, or nil if the queue is empty.

    :return: an element, or nil
  */

  func dequeue() -> Element?
}