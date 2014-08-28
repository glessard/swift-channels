swift-channels
==============

Channels to safely pass data between asynchronous tasks in swift.

This library contains concurrency constructs for use in Swift, tested on
Mac OS X.

The concurrency model I attempted to reach is similar to that of Go,
wherein concurrent threads are encouraged to synchronize and share data
through constrained channels. This is also somewhat similar to the
concurrency model of Labview, in that the program execution could be
organized around the flow of data through channels.

The main part of this is a channel (Chan<T>) class that models sending
and receiving (strongly typed) messages on a bounded queue. Message
sending is achieved with an infix '<-' operator (as in Go); this
operation will block whenever the channel is full. Message receiving is
achieved with an unary prefix '<-' operator; this operation will block
whenever the channel is empty.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). At the moment only the 1-element buffer works, though that
appears to be an unintentional regression in the beta 6 compiler (longer
buffers did work earlier.)

Also included is an 'async' pseudo-keyword, as shortcut for the Grand
Central Dispatch method for launching a closure asynchronously in the
background.

Example:
```
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

This will count up to 10 on a background task, while printing the
results on the main thread. The while loop will then exit since the
channel will have been closed. An empty, closed channel returns nil,
thereby signaling to receivers that it has become closed.

Missing from this is anything like the Select keyword in Go, which is
quite useful when dealing with multiple channels at once. I have
ideas.

Also missing is anything that will help figure out deadlocks. They will
happen!

I welcome questions and suggestions