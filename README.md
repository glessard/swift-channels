swift-channels
==============

This library contains concurrency constructs for use in Swift.

The concurrency model this attempts to achieve is similar to that of
Go, wherein concurrent threads are encouraged to synchronize and share
data chiefly through type-constrained channels.

The main part of this is a channel (`Chan<T>`) class that models
sending and receiving (strongly typed) messages on a bounded
queue. By default, Channel creation returns a tuple of objects that act
as the endpoints of the channel: `Sender<T>` and `Receiver<T>`.

Sending on the channel is achieved with an infix `<-` operator on the
`Sender` object; this operation will block whenever the channel is
full. Receiving from the channel is achieved with an unary prefix `<-`
operator on the `Receiver` object; this operation will block whenever
the channel is empty.

A channel can be closed by invoking the `close()` method on either the
Sender or the Receiver, though closing via the Sender should be more
useful. Receive operations on a closed channel continue normally until
the channel is drained. Receiving from a closed, empty channel returns nil.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). A buffered channel can store a certain number of
elements, after which the next send operation will block.

Thread blocking and thread spawning is implemented with libdispatch
(aka GCD); a pthreads-based implementation of thread blocking exists as
subclasses of `PChan`. The pthreads implementations are not quite as
fast as the libdispatch semaphore versions.

Along with a channels implementation, this library includes an `async`
pseudo-keyword, a simple shortcut to launch a closure asynchronously
in the background with GCD. The only requirement for a closure
launched via `async` is that it have no parameters. A return value
will be ignored if it exists.

Missing from this is a powerful construct such as the Select keyword
from Go, which would be quite useful when dealing with multiple
channels at once.

#### Example:
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

#### Performance

On OS X, with Swift 1.2, message transmission with no thread contention
takes about 25% longer as it would in Go, e.g. 200 vs. 160 nanoseconds
on a 2008 Mac Pro. It is possible to narrow the gap, but that would
require compromises that are likely to be obviated by future compiler
improvements. With thread contention, this library is *much* slower than
Go channels, due to the time it takes to swap threads. Message transmission
through unbuffered channels takes just a bit longer than two thread swaps,
which is about right.

I welcome questions and suggestions.
