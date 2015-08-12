//
//  queued-semaphore.swift
//  Channels
//
//  Created by Guillaume Lessard on 2015-08-12.
//  Copyright © 2015 Guillaume Lessard. All rights reserved.
//

/// A struct to enable enqueuing `ChannelSemaphore` references that could represent
/// either a simple `put` or `get` operation, or a `select` operation.

struct QueuedSemaphore
{
  let sem: ChannelSemaphore
  let sel: Selection!

  init(_ s: ChannelSemaphore)
  {
    sem = s
    sel = nil
  }

  init(_ sem: ChannelSemaphore, _ sel: Selection)
  {
    self.sem = sem
    self.sel = sel
  }
}
