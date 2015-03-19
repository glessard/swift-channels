//
//  qchan.swift
//  concurrency
//
//  Created by Guillaume Lessard on 2015-01-14.
//  Copyright (c) 2015 Guillaume Lessard. All rights reserved.
//

public class QChan<T>
{
  public class func Make(capacity: Int) -> Chan<T>
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
