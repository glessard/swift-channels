//
//  defer.swift
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

private class DeferredTasks
{
  private typealias Task = () -> ()
  var list = [Task]()

  deinit
  {
    for task in list.reverse()
    {
      task()
    }
  }
}

struct Deferred
{
  private var d = DeferredTasks()

  init() { }

  init(_ task: () -> ())
  {
    d.list.append(task)
  }

  init<IgnoredType>(task: () -> IgnoredType)
  {
    d.list.append { _ = task() }
  }

  func defer(task: () -> ())
  {
    d.list.append(task)
  }

  func defer<IgnoredType>(task: () -> IgnoredType)
  {
    d.list.append { _ = task() }
  }
}


private func test()
{
  var T = Deferred {println("last thing to happen.")}

  var f1 = "fileref 1"
  T.defer {println("close " + f1)}
  println(f1 + " is ready for use")

  var f2 = "fileref 2"
  T.defer {println("close " + f2)}
  println(f2 + " is ready for use")

  println("do things with " + f1 + " and " + f2)
}
