//
//  schan.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-01-14.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

public class SChan<T>
{
  public class func Make(capacity: Int) -> Chan<T>
  {
    // Note that an SBufferedChan with a capacity of 0 *will* deadlock.
    return SBufferedChan<T>((capacity < 1) ? 0 : capacity)
  }
}
