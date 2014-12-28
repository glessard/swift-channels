//
//  atomiclinknodes.m
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-27.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

#import <libkern/OSAtomic.h>
#import "linknode.h"

size_t PointerNodeLinkOffset()
{
  return offsetof(struct PointerNode, next);
}

size_t PointerNodeSize()
{
  return sizeof(struct PointerNode);
}
