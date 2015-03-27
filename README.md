swift-channels
==============

This library implements channel classes to help with communication between
asynchronous tasks in Swift. These channels are similar to those
in Go, wherein concurrent tasks are encouraged to synchronize and share
data chiefly through type-constrained channels.

The main attractions are `Sender<T>` and `Receiver<T>`. They respectively
implement sending and receiving (strongly typed) messages on synchronized,
bounded queues. They are created as a tuple when a channel is initialized.

Send data on the channel with the infix `<-` operator on a
`Sender` object; this will block whenever the channel is full.
Receive data from the channel with the unary prefix `<-`
operator on a `Receiver` object; this will block whenever
the channel is empty.

A channel can be closed by invoking the `close()` method on either the
Sender or the Receiver, though closing via the Sender should be more
useful. Receive operations on a closed channel continue normally until
the channel is drained. Receiving from a closed, empty channel returns nil.

Channels can be used in buffered and unbuffered form. In an unbuffered
channel a receive operation will block until a sender is ready (and
vice-versa). A buffered channel can store a certain number of
elements, after which the next send operation will block.

Thread synchronization and blocking is implemented with libdispatch semaphores
(`dispatch_semaphore_t`); an implementation based on pthreads mutexes exists
in subclasses of `PChan`. The pthreads implementation is significantly slower
than the the libdispatch semaphore version.

Missing from this is a powerful construct such as the Select keyword
from Go, which would be quite useful when dealing with multiple
channels at once. See the `select` branch for details.

#### Example:
```
import Darwin
import Dispatch

let (sender, receiver) = Channel<Int>.Make()

dispatch_async(dispatch_get_global_queue(qos_class_self(), 0)) {
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
operation. The `while` loop will then exit when the channel is
closed by `sender.close()`. Attempting to receive from a channel that
is both empty and closed returns nil.
This causes the while loop in the example to exit.

#### Performance

On OS X, with Swift 1.2 and whole-module optimization,
message transmission with no thread contention is slightly faster as
it would be in Go 1.4, e.g. 140 vs. 160 nanoseconds on a 2008 Mac Pro
(2.8 GHz Xeon "Harpertown" (E5462)).
With thread contention, Go channels are *much* faster (about 10x),
due to the context switching time involving dispatch semaphores. Go has a
very lightweight concurrency system, while dispatch_semaphore pause and
resume system threads.

Message transmission through this library's unbuffered channel type
takes about the same time as two context switches, and that
is about as good as can be expected.

I welcome questions and suggestions.
