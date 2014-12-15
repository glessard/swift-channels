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

OSFifoQueueHead* AtomicQueueInit();

void AtomicQueueRelease(OSFifoQueueHead* h);


void AtomicQueueEnqueue(OSFifoQueueHead* h, id item);

id   AtomicQueueDequeue(OSFifoQueueHead* h);

long AtomicQueueRealCount(OSFifoQueueHead* h);

#endif
