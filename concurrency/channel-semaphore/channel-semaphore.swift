//
//  Semaphore.swift
//  LightweightSemaphore
//
//  Created by Guillaume Lessard on 2015-04-03.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

import Darwin.Mach.task
import Darwin.Mach.semaphore
import Darwin.Mach.mach_time
import Darwin.libkern.OSAtomic

/**
  A [benaphore](http://www.haiku-os.org/legacy-docs/benewsletter/Issue1-26.html)
  (see also [this](http://preshing.com/20120226/roll-your-own-lightweight-mutex/)).

  Much like `dispatch_semaphore_t`, with native Swift typing, state information and associated data.
  See libdispatch [here](http://www.opensource.apple.com/source/libdispatch/).
*/

final public class ChannelSemaphore
{
  // MARK: init/deinit

  init()
  {
    svalue = 0
    semp = MachSemaphorePool.Obtain()
  }

  deinit
  {
    precondition(svalue == 0, "ChannelSemaphore abandoned with a non-zero svalue (\(svalue)) in \(#function)")

    MachSemaphorePool.Return(semp)
  }

  // MARK: State Handling

  enum State: Int32
  {
    case ready

    // Unbuffered channel data
    case pointer

    // Select() case
    case waitSelect
    case select
    case doubleSelect
    case invalidated
    
    // End state
    case done
  }
  
  fileprivate var currentState = State.ready.rawValue

  var state: State { return State(rawValue: currentState)! }

  @discardableResult
  func setState(_ newState: State) -> Bool
  {
    switch newState
    {
    case .ready:
      return currentState == State.ready.rawValue ||
             OSAtomicCompareAndSwap32Barrier(State.done.rawValue, State.ready.rawValue, &currentState)

    case .pointer, .waitSelect:
      return OSAtomicCompareAndSwap32Barrier(State.ready.rawValue, newState.rawValue, &currentState)

    case .select, .doubleSelect:
      return OSAtomicCompareAndSwap32Barrier(State.waitSelect.rawValue, newState.rawValue, &currentState)

    case .invalidated:
      // shift directly to the .Done state
      return OSAtomicCompareAndSwap32Barrier(State.waitSelect.rawValue, State.done.rawValue, &currentState)

    case .done:
      // Ideally it would be: __sync_swap(&currentState, State.Done.rawValue)
      // Or maybe: __c11_atomic_store(&currentState, State.Done.rawValue, __ATOMIC_SEQ_CST)
      repeat {} while OSAtomicCompareAndSwap32Barrier(currentState, State.done.rawValue, &currentState) == false
      return true
    }
  }

  // MARK: Data handling

  /**
    An associated pointer to pass data synchronously between threads.
  */

  fileprivate var iptr: UnsafeMutableRawPointer? = nil

  /**
    Set this `ChannelSemaphore`'s associated pointer.

    This accessor is necessary in order to be able to do the following:
    ```
    var element = T()
    semaphore.setPointer(&element)
    ```
    This is due to the fact that typecasting the address of a variable to an `UnsafeMutablePointer<Void>` is not possible.
  
    - parameter p: The address of a variable or a pointer.
  */

  final func setPointer<T>(_ p: UnsafeMutablePointer<T>)
  {
    if currentState == State.pointer.rawValue ||
       currentState == State.doubleSelect.rawValue
    { iptr = UnsafeMutableRawPointer(p) }
    else
    { iptr = nil }
  }

  final var pointer: UnsafeMutableRawPointer? {
    get {
      if currentState == State.pointer.rawValue ||
         currentState == State.doubleSelect.rawValue
      { return iptr }
      else
      { return nil }
    }
    set {
      if currentState == State.pointer.rawValue ||
         currentState == State.doubleSelect.rawValue
      { iptr = newValue }
      else
      { iptr = nil }
    }
  }

  /**
    Data structure to work with the `select_chan()` function.
  */

  fileprivate var seln: Selection? = nil

  final var selection: Selection! {
    get {
      if currentState == State.select.rawValue ||
         currentState == State.doubleSelect.rawValue
      { return seln }
      else
      { return nil }
    }
    set {
      if currentState == State.select.rawValue ||
         currentState == State.doubleSelect.rawValue
      { seln = newValue }
      else
      { seln = nil }
    }
  }

  // MARK: Semaphore functionality

  fileprivate var svalue: Int32
  fileprivate let semp: semaphore_t

  func signal()
  {
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return

    case Int32.min:
      fatalError("Semaphore signaled too many times")

    default: break
    }

    let kr = semaphore_signal(semp)
    precondition(kr == KERN_SUCCESS)
  }

  func wait()
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return
    }

    while case let kr = semaphore_wait(semp), kr != KERN_SUCCESS
    {
      guard kr == KERN_ABORTED else { fatalError("Bad response (\(kr)) from semaphore_wait() in \(#function)") }
    }
  }
}
