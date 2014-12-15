//
//  atomicqueue.m
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AtomicQueue.h"

OSFifoQueueHead* AtomicQueueInit()
{
  return (OSFifoQueueHead*) calloc(1, sizeof(OSFifoQueueHead));
}

void AtomicQueueRelease(OSFifoQueueHead* h)
{
  free((void*)h);
}


struct QueueElement
{
  struct QueueElement* next;
  CFTypeRef            item;
};

void AtomicQueueEnqueue(OSFifoQueueHead* h, id item)
{
  struct QueueElement* qe = calloc(1, sizeof(struct QueueElement));
  qe->item = CFBridgingRetain(item);
  OSAtomicFifoEnqueue(h, qe, offsetof(struct QueueElement, next));
}

id AtomicQueueDequeue(OSFifoQueueHead* h)
{
  id item = NULL;
  struct QueueElement* qe = OSAtomicFifoDequeue(h, offsetof(struct QueueElement, next));

  if (qe != NULL)
  {
    item = CFBridgingRelease(qe->item);
    free(qe);
  }

  return item;
}

long AtomicQueueRealCount(OSFifoQueueHead* h)
{
  long count = 0;

  if (h->opaque1 != NULL)
  {
    struct QueueElement* qe = (struct QueueElement*) h->opaque1;
    count++;

    while (qe->next != NULL)
    {
      qe = qe->next;
      count++;
    }
  }
  return count;
}
