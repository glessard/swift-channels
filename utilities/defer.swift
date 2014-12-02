//
//  defer.swift
//
//  Created by Guillaume Lessard on 2014-08-29.
//  Copyright (c) 2014 Guillaume Lessard. All rights reserved.
//

private class TaskList
{
  private typealias Task = () -> ()
  var list = [Task]()

  func append(task: Task)
  {
    list.append(task)
  }

  deinit
  {
    for task in list.reverse()
    {
      task()
    }
  }
}

struct DeferredTaskList
{
  private var tasklist = TaskList()

  func defer(task: () -> ())
  {
    tasklist.append(task)
  }

  func defer<IgnoredType>(task: () -> IgnoredType)
  {
    tasklist.append { _ = task() }
  }
}


private func test()
{
  var T = DeferredTaskList()

  var f1 = "fileref 1"
  T.defer {println("close " + f1)}
  println(f1 + " is ready for use")

  var f2 = "fileref 2"
  T.defer {println("close " + f2)}
  println(f2 + " is ready for use")

  println("do things with " + f1 + " and " + f2)
}
