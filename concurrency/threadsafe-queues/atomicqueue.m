//
//  atomicqueue.m
//  concurrency
//
//  Created by Guillaume Lessard on 2014-12-13.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AtomicQueue.h"

/**
 Initialize a new queue head.
 Note that officially, the initialization vector is OS_ATOMIC_FIFO_QUEUE_INIT,
 defined as { NULL, NULL, 0 }. Using calloc() seems just as good.
 */

OSFifoQueueHead* AtomicQueueInit()
{
  return (OSFifoQueueHead*) calloc(1, sizeof(OSFifoQueueHead));
}

/**
 Delete a queue head.
 Empty the queue before calling this.
 */

void AtomicQueueRelease(OSFifoQueueHead* h)
{
  free((void*)h);
}

/**
 Simple linked-list node for an ARC-aware queue based on OSAtomicQueue
 */

struct idNode
{
  struct idNode* next;
  CFTypeRef      item;
};

/**
 Allocate a new node, assign item to it, enqueue the node.
 */

void idEnqueue(OSFifoQueueHead* h, id item)
{
  struct idNode* n = calloc(1, sizeof(struct idNode));
  n->item = CFBridgingRetain(item);
  OSAtomicFifoEnqueue(h, n, offsetof(struct idNode, next));
}

/**
 Dequeue a node, get the item if it exists, return the item (or nil)
 */

id idDequeue(OSFifoQueueHead* h)
{
  id item = NULL;
  struct idNode* n = OSAtomicFifoDequeue(h, offsetof(struct idNode, next));

  if (n != NULL)
  {
    item = CFBridgingRelease(n->item);
    free(n);
  }

  return item;
}

/**
  For verification only. This function depends on the deduced workings
  of the OSAtomicQueue functions. Bound to fail eventually.
 */

long idQueueRealCount(OSFifoQueueHead* h)
{
  long count = 0;

  if (h->opaque1 != NULL)
  {
    struct idNode* n = (struct idNode*) h->opaque1;
    count++;

    while (n->next != NULL)
    {
      n = n->next;
      count++;
    }
  }
  return count;
}


/**
  Simple linked-list node in C for OSAtomicQueue
 */

struct ptrNode
{
  struct ptrNode* next;
  void*           item;
};

/**
 Allocate a new node, assign item to it, enqueue the node.
 */

void ptrEnqueue(OSFifoQueueHead* h, void* item)
{
  struct ptrNode* n = calloc(1, sizeof(struct ptrNode));
  n->item = item;
  OSAtomicFifoEnqueue(h, n, offsetof(struct ptrNode, next));
}

/**
 Dequeue a node, get the item if it exists, return the item (or nil)
 */

void* ptrDequeue(OSFifoQueueHead* h)
{
  void* item = NULL;
  struct ptrNode* n = OSAtomicFifoDequeue(h, offsetof(struct ptrNode, next));

  if (n != NULL)
  {
    item = n->item;
    free(n);
  }

  return item;
}

/**
 For verification only. This function depends on the deduced workings
 of the OSAtomicQueue functions. Bound to fail eventually.
 */

long ptrQueueRealCount(OSFifoQueueHead* h)
{
  long count = 0;

  if (h->opaque1 != NULL)
  {
    struct ptrNode* n = (struct ptrNode*) h->opaque1;
    count++;

    while (n->next != NULL)
    {
      n = n->next;
      count++;
    }
  }
  return count;
}
