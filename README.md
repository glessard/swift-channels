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

The main part of this is a channel (`Chan<T>`) class that models
sending and receiving (strongly typed) messages on a bounded
queue. Message sending is achieved with an infix `<-` operator (as in
Go); this operation will block whenever the channel is full. Message
receiving is achieved with an unary prefix `<-` operator; this
operation will block whenever the channel is empty. A sender can
signal task completion by closing a channel. Further sends have no
effect, while receive continue normally until the channel is
drained. Receiving from a closed, empty channel returns nil.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). A buffered channel can store a certain number of
elements, after which the next send operation will block.

Thread blocking is implemented with pthreads mutex locks and condition
variables, while threads are spawned with Grand Central Dispatch
(GCD). Thread blocking can be successfully implemented with GCD, but
it is slower. A GCD-based channel implementation can be found on the
`gcd-channels` branch.

Along with a channels implementation, this library includes an `async`
pseudo-keyword, a simple shortcut to launch a closure asynchronously
in the background with GCD. The only requirement for a closure
launched via `async` is that it have no parameters. A return value
will be ignored if it exists.

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
from Go, which is quite useful when dealing with multiple channels at
once. There is an initial implementation, but runtime stability
currently requires every channel to be of the same type, which greatly
weakens the construct.

Also missing is a deadlock detector. Deadlocks will happen! They
don't have to. Good luck.

I welcome questions and suggestions
