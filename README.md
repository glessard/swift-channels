swift-channels
==============

Channels to safely pass data between asynchronous tasks in swift.

This library contains concurrency constructs for use in Swift, tested on
Mac OS X.

The concurrency model this attempts to achieve is similar to that of
Go, wherein concurrent threads are encouraged to synchronize and share
data through constrained channels. This is also somewhat similar to
the concurrency model of Labview, in that the execution of major nodes
in the program could be organized around the flow of data through
channels.

The main part of this is a channel (`Chan<T>`) class that models sending
and receiving (strongly typed) messages on a bounded queue. Message
sending is achieved with an infix `<-` operator (as in Go); this
operation will block whenever the channel is full. Message receiving is
achieved with an unary prefix `<-` operator; this operation will block
whenever the channel is empty.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). At the moment only the 1-element buffer works, though
that appears to be an unintentional regression in the beta 6 compiler;
given that the existing implementation of longer buffers worked
earlier, it is likely that it will work again.

The thread blocking logic is implemented using pthreads mutexes, while
the thread spawning logic uses Grand Central Dispatch (GCD). It may be
possible to drop pthread mutexes entirely; stay tuned.

Along with a channels implementation, this library includes an `async`
pseudo-keyword, as shortcut for the GCD method for launching a closure
asynchronously in the background. The only requirement for a closure
launched via `async` is that it have no parameters -- an easily
achieved requirement. A return value will be ignored if it exists.

Example:
```
import Darwin

let ch = Chan<Int>.Make()

async {
  for i in 1...10
  {
    ch <- i
    sleep(1)
  }
  ch.close()
}

while let m = <-ch
{
  println(m)
}
```

The `for` loop will count up to 10 on a background thread, sending
results to the main thread, which prints them. The main thread pauses
while waiting for results inside the `<-ch` channel read
operation. The `while` loop will then exit when the channel becomes
closed. An empty, closed channel returns nil, thereby signaling to
receivers that it has become closed.

Missing from this is a powerful construct such as the Select keyword
in Go, which is quite useful when dealing with multiple channels at
once. The channel-select branch has an initial implementation, but
runtime stability currently requires every channel to be of the same
type, which greatly weakens the construct.

Also missing is anything that can predict deadlocks. They will happen!
They don't have to. Good luck.

I welcome questions and suggestions
