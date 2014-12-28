//
//  atomicqueue.h
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

#ifndef atomicqueue_h
#define atomicqueue_h

#import <Foundation/Foundation.h>

/**
 Initialize a new queue head.
*/
 
OSFifoQueueHead* AtomicQueueInit();

/**
 Delete a queue head.
 Empty the queue before calling this.
 */

void AtomicQueueRelease(OSFifoQueueHead* h);

/**
 Count the number of nodes attached to a queue head.
 For verification only. This function depends on the deduced workings
 of the OSAtomicQueue functions. Bound to fail eventually.
 Certainly not atomic or threadsafe in any way whatsoever.
 */

long AtomicQueueCountNodes(OSFifoQueueHead* h, size_t offset);


/**
 For an ARC-aware queue, use idEnqueue and idDequeue
 */

void idEnqueue(OSFifoQueueHead* h, id item);

id   idDequeue(OSFifoQueueHead* h);

long idQueueRealCount(OSFifoQueueHead* h);

/**
 For an ARC-oblivious queue, use ptrEnqueue and ptrDequeue
 */

void  ptrEnqueue(OSFifoQueueHead* h, void* item);

void* ptrDequeue(OSFifoQueueHead* h);

long  ptrQueueRealCount(OSFifoQueueHead* h);

#endif
