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
  An object reuse pool for `ChannelSemaphore`.
  A mach semaphore (obtained with `semaphore_create`) takes several microseconds to create.
  Without a reuse pool, this cost would be incurred every time a thread needs to stop
  in `QUnbufferedChan`, `QBufferedChan` and `select_chan()`. Reusing reduces the cost to
  much less than 1 microsecond.
*/

struct SemaphorePool
{
  static private let capacity = 256
  static private let buffer = UnsafeMutablePointer<ChannelSemaphore>.alloc(capacity)
  static private var cursor = 0

  static private var lock = OS_SPINLOCK_INIT

  /**
    Return a `ChannelSemaphore` to the reuse pool.
    - parameter s: A `ChannelSemaphore` to return to the reuse pool.
  */

  static func Return(s: ChannelSemaphore)
  {
    OSSpinLockLock(&lock)
    if cursor < capacity
    {
      buffer.advancedBy(cursor).initialize(s)
      cursor += 1
      assert(s.svalue == 0, "Non-zero user-space semaphore count of \(s.svalue) in \(__FUNCTION__)")
      assert(s.seln == nil || s.state == .DoubleSelect, "Unexpectedly non-nil Selection in \(__FUNCTION__)")
      assert(s.iptr == nil || s.state == .DoubleSelect, "Non-nil pointer \(s.iptr) in \(__FUNCTION__)")
    }
    OSSpinLockUnlock(&lock)
  }

  /**
    Obtain a `ChannelSemaphore` from the object reuse pool.
    The returned `ChannelSemaphore` will be uniquely referenced.
    - returns: A uniquely-referenced `ChannelSemaphore`.
  */

  static func Obtain() -> ChannelSemaphore
  {
    OSSpinLockLock(&lock)
    if cursor > 0
    {
      cursor -= 1
      for var i=cursor; i>=0; i--
      {
        if isUniquelyReferencedNonObjC(&buffer[i])
        {
          var s = buffer.advancedBy(cursor).move()
          if i < cursor
          {
            swap(&s, &buffer[i])
          }
          OSSpinLockUnlock(&lock)

          // Expected state:
          // s.svalue = 0
          // s.seln = nil
          // s.iptr = nil
          s.currentState = ChannelSemaphore.State.Ready.rawValue
          return s
        }
      }
      cursor += 1
    }
    OSSpinLockUnlock(&lock)
    return ChannelSemaphore()
  }
}

/**
  A [benaphore](http://www.haiku-os.org/legacy-docs/benewsletter/Issue1-26.html)
  (see also [this](http://preshing.com/20120226/roll-your-own-lightweight-mutex/)).

  Much like `dispatch_semaphore_t`, with native Swift typing, state information and associated data.
  See libdispatch [here](http://www.opensource.apple.com/source/libdispatch/).
*/

final public class ChannelSemaphore
{
  // MARK: init/deinit

  init(value: Int)
  {
    svalue = (value < 0) ? 0 : Int32(min(value, Int(Int32.max)))
  }

  convenience init()
  {
    self.init(value: 0)
  }

  deinit
  {
    if semp != 0
    {
      let kr = semaphore_destroy(mach_task_self_, semp)
      assert(kr == KERN_SUCCESS, __FUNCTION__)
    }
  }

  final private func initSemaphorePort()
  {
    var port = semaphore_t()
    let kr = semaphore_create(mach_task_self_, &port, SYNC_POLICY_FIFO, 0)
    assert(kr == KERN_SUCCESS, __FUNCTION__)

    let success: Bool = { (ptr: UnsafeMutablePointer<UInt32>) -> Bool in
      return OSAtomicCompareAndSwap32Barrier(0, unsafeBitCast(port, Int32.self), UnsafeMutablePointer<Int32>(ptr))
    }(&semp)

    if !success
    { // another initialization attempt succeeded concurrently. Don't leak the port; return it.
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
    case .Pointer, .WaitSelect:
      return OSAtomicCompareAndSwap32Barrier(State.Ready.rawValue, newState.rawValue, &currentState)

    case .Select, .Invalidated, .DoubleSelect:
      return OSAtomicCompareAndSwap32Barrier(State.WaitSelect.rawValue, newState.rawValue, &currentState)

    case .Done:
      // Ideally it would be: __sync_swap(&currentState, State.Done.rawValue)
      // Or maybe: __c11_atomic_exchange(&currentState, State.Done.rawValue, __ATOMIC_SEQ_CST)
      while OSAtomicCompareAndSwap32Barrier(currentState, State.Done.rawValue, &currentState) == false {}
      return true

    default:
      return false
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
  private var semp = semaphore_t()

  func signal() -> Bool
  {
    switch OSAtomicIncrement32Barrier(&svalue)
    {
    case let v where v > 0:
      return false

    case Int32.min:
      preconditionFailure("Semaphore signaled too many times")

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

    if semp == 0 { initSemaphorePort() }

    while case let kr = semaphore_wait(semp) where kr != KERN_SUCCESS
    {
      guard kr == KERN_ABORTED else { preconditionFailure("Bad response (\(kr)) from semaphore_wait() in \(__FUNCTION__)") }
    }
    return true
  }
}
