swift-channels
==============

This library contains concurrency constructs for use in Swift, tested on
Mac OS X.

The concurrency model this attempts to achieve is similar to that of
Go, wherein concurrent threads are encouraged to synchronize and share
data chiefly through type-constrained channels. This is also somewhat
similar to the concurrency model of Labview, in that the execution of
major nodes in the program can be organized around the flow of data
through channels.

The main part of this is a channel (`Chan<T>`) class that models
sending and receiving (strongly typed) messages on a bounded
queue. Channel creation returns a tuple of objects that model
the endpoints of the channel (as in Rust).

Sending on the channel is achieved with an infix `<-` operator on the
Sender object; this operation will block whenever the channel is
full. Receiving from the channel is achieved with an unary prefix `<-`
operator on the Receiver object; this operation will block whenever
the channel is empty.

A channel can be closed by invoking the `close()` method on either the
Sender or the Receiver, though closing via the Sender should be more
useful. Further sends on a closed channel have no effect, while
receive operations continue normally until the channel is
drained. Receiving from a closed, empty channel returns nil.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). A buffered channel can store a certain number of
elements, after which the next send operation will block.

Thread blocking is implemented with pthreads mutex locks and condition
variables, while threads are spawned with Grand Central Dispatch
(GCD). Thread blocking can be successfully implemented with GCD, but
it is slower. A GCD-based channel implementation can be found in the
file `concurrency/chan-blocks.swift`. It is a drop-in replacement for
`chan-pthreads.swift`

Along with a channels implementation, this library includes an `async`
pseudo-keyword, a simple shortcut to launch a closure asynchronously
in the background with GCD. The only requirement for a closure
launched via `async` is that it have no parameters. A return value
will be ignored if it exists.

Example:
```
import Darwin

let (sender, receiver) = Channel<Int>.Make()

async {
  for i in 1...10
  {
    sender <- i
    sleep(1)
  }
  sender.close()
}

while let m = <-receiver
{
  println(m)
}
```

The `for` loop will count up to 10 on a background thread, sending
results to the main thread, which prints them. The main thread pauses
while waiting for results inside `<-receiver`, the channel receive
operation. The `while` loop will then exit when the channel becomes
closed. Receiving from a channel that is both empty and closed returns
nil, thereby signaling that the channel has become closed.

Missing from this is a powerful construct such as the Select keyword
from Go, which is quite useful when dealing with multiple channels at
once. There is an initial implementation that is both unstable and
slow, on the `channel-select` branch.

I welcome questions and suggestions.
