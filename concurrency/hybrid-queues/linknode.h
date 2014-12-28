//
//  linknode.h
//  QQ
//
//  Created by Guillaume Lessard on 2014-12-27.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

#ifndef QQ_linknode_h
#define QQ_linknode_h

struct PointerNode
{
  struct PointerNode* next;
  void*              item;
};

size_t PointerNodeLinkOffset();
size_t PointerNodeSize();

#endif
