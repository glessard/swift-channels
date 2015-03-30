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
  
    :param: newElement the initial element of the new queue
  */

  init(_ newElement: Element)

  /**
    Return whether the queue is empty
  */

  var isEmpty: Bool { get }

  /**
    Return the number of elements currently in the queue.
    For some implementations, it might be faster to check for queue length
    rather than attempting a dequeue on an empty queue. For those cases,
    this would be the fast check.
  */

  var count: Int { get }

  /**
    Add a new element to the queue.
  
    :param: newElement a new element
  */

  func enqueue(newElement: Element)

  /**
    Return the oldest element from the queue, or nil if the queue is empty.

    :return: an element, or nil
  */

  func dequeue() -> Element?


  /**
    For testing, mostly. Walk the linked list while counting the nodes.
  */

  func countElements() -> Int
}