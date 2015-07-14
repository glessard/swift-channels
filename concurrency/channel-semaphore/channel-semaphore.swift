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
import Dispatch.time

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
    semp = semaphore_t()
  }

  deinit
  {
    precondition(svalue == 0, "ChannelSemaphore abandoned with a non-zero svalue (\(svalue)) in \(__FUNCTION__)")

    if semp != 0
    {
      while case let kr = semaphore_timedwait(semp, mach_timespec_t(tv_sec: 0,tv_nsec: 0))
      where kr != KERN_OPERATION_TIMED_OUT
      {
        print(kr)
        guard kr == KERN_SUCCESS || kr == KERN_ABORTED else
        { fatalError("\(kr) in \(__FUNCTION__)") }
      }
      MachSemaphorePool.Return(semp)
    }
  }

  private func initSemaphorePort()
  {
    let port = MachSemaphorePool.Obtain()

    if CAS(0, port, &semp) == false
    { // another initialization attempt succeeded concurrently. Don't leak the port: destroy it properly.
      let kr = semaphore_destroy(mach_task_self_, port)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }

  // MARK: State Handling

  enum State: Int32
  {
    case Ready

    // Unbuffered channel data
    case Pointer

    // Select() case
    case WaitSelect
    case Select
    case DoubleSelect
    case Invalidated
    
    // End state
    case Done
  }
  
  private var currentState = State.Ready.rawValue

  var state: State { return State(rawValue: currentState)! }

  func setState(newState: State) -> Bool
  {
    switch newState
    {
    case .Ready:
      return currentState == State.Ready.rawValue ||
             OSAtomicCompareAndSwap32Barrier(State.Done.rawValue, State.Ready.rawValue, &currentState)

    case .Pointer, .WaitSelect:
      return OSAtomicCompareAndSwap32Barrier(State.Ready.rawValue, newState.rawValue, &currentState)

    case .Select, .DoubleSelect:
      return OSAtomicCompareAndSwap32Barrier(State.WaitSelect.rawValue, newState.rawValue, &currentState)

    case .Invalidated:
      // shift directly to the .Done state
      return OSAtomicCompareAndSwap32Barrier(State.WaitSelect.rawValue, State.Done.rawValue, &currentState)

    case .Done:
      // Ideally it would be: __sync_swap(&currentState, State.Done.rawValue)
      // Or maybe: __c11_atomic_store(&currentState, State.Done.rawValue, __ATOMIC_SEQ_CST)
      repeat {} while OSAtomicCompareAndSwap32Barrier(currentState, State.Done.rawValue, &currentState) == false
      return true
    }
  }

  // MARK: Data handling

  /**
    An associated pointer to pass data synchronously between threads.
  */

  private var iptr: UnsafeMutablePointer<Void> = nil

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

  final func setPointer<T>(p: UnsafeMutablePointer<T>)
  {
    if currentState == State.Pointer.rawValue ||
       currentState == State.DoubleSelect.rawValue
    { iptr = UnsafeMutablePointer(p) }
    else
    { iptr = nil }
  }

  final var pointer: UnsafeMutablePointer<Void> {
    get {
      if currentState == State.Pointer.rawValue ||
         currentState == State.DoubleSelect.rawValue
      { return iptr }
      else
      { return nil }
    }
    set {
      if currentState == State.Pointer.rawValue ||
         currentState == State.DoubleSelect.rawValue
      { iptr = newValue }
      else
      { iptr = nil }
    }
  }

  /**
    Data structure to work with the `select_chan()` function.
  */

  private var seln: Selection? = nil

  final var selection: Selection! {
    get {
      if currentState == State.Select.rawValue ||
         currentState == State.DoubleSelect.rawValue
      { return seln }
      else
      { return nil }
    }
    set {
      if currentState == State.Select.rawValue ||
         currentState == State.DoubleSelect.rawValue
      { seln = newValue }
      else
      { seln = nil }
    }
  }

  // MARK: Semaphore functionality

  private var svalue: Int32
  private var semp: semaphore_t

  func signal() -> Bool
  {
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return false

    case Int32.min:
      fatalError("Semaphore signaled too many times")

    default: break
    }

    while semp == 0
    { // if svalue was previously less than zero, there must be a wait() call
      // currently in the process of initializing semp.
      usleep(1)
      OSMemoryBarrier()
    }

    return (semaphore_signal(semp) == KERN_SUCCESS)
  }

  func wait() -> Bool
  {
    if OSAtomicDecrement32Barrier(&svalue) >= 0
    {
      return true
    }

    if semp == 0
    {
      initSemaphorePort()
      OSMemoryBarrier()
    }

    while case let kr = semaphore_wait(semp) where kr != KERN_SUCCESS
    {
      guard kr == KERN_ABORTED else { fatalError("Bad response (\(kr)) from semaphore_wait() in \(__FUNCTION__)") }
    }
    return true
  }
}
