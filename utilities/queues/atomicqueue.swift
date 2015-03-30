//
//  atomicqueue.swift
//  QQ
//
//  Created by Guillaume Lessard on 2015-01-09.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//


/*
  Initialize an OSFifoQueueHead struct, even though we don't
  have its definition from Swift. See libkern/OSAtomic.h
*/

#if os(OSX)

typealias QueueHead = COpaquePointer

func AtomicQueueInit() -> QueueHead
{
  // There are 3 values in OSAtomicFifoQueueHead, but the struct
  // is aligned on 16-byte boundaries on x64, translating to 32 bytes.
  // As a workaround, we assign a chunk of 4 integers.

  // From libkern/OSAtomic.h:
  //  typedef	volatile struct {
  //    void	*opaque1;
  //    void	*opaque2;
  //    int	 opaque3;
  //  } __attribute__ ((aligned (16))) OSFifoQueueHead;

  let h = UnsafeMutablePointer<Int>.alloc(4)
  for i in 0..<4
  {
    h.advancedBy(i).memory = 0
  }

  return COpaquePointer(h)
}

func AtomicQueueRelease(h: QueueHead)
{
  UnsafeMutablePointer<Int>(h).dealloc(4)
}

#endif

/*
  Initialize an OSQueueHead struct, even though we don't
  have its definition from Swift. See libkern/OSAtomic.h
*/

typealias StackHead = COpaquePointer

func AtomicStackInit() -> StackHead
{
  // From libkern/OSAtomic.h:
  //  typedef volatile struct {
  //    void	*opaque1;
  //    long	 opaque2;
  //  } __attribute__ ((aligned (16))) OSQueueHead;

  let h = UnsafeMutablePointer<Int>.alloc(2)
  for i in 0..<2
  {
    h.advancedBy(i).memory = 0
  }

  return COpaquePointer(h)
}

func AtomicStackRelease(h: StackHead)
{
  UnsafeMutablePointer<Int>(h).dealloc(2)
}
