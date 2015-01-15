//
//  qchan.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-01-14.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

public class QChan<T>
{
  public class func Make(capacity: Int, queue: Bool = false) -> Chan<T>
  {
    switch capacity < 1
    {
    case true:
      return QUnbufferedChan<T>()

    default:
      return QBufferedChan<T>(capacity)
    }
  }
}
