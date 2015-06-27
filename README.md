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

Channels can be used in buffered and unbuffered form. Sending and receiving
on an unbuffered channel are synchronous operations: the operation will
block until the message can be sent or received. A buffered channel can
store a certain number of elements, after which the next send operation will block.
Note that in steady-state, a buffered channel can be expected to be either
always empty or always full, therefore unbuffered channels should be preferred.

Thread synchronization and blocking is implemented with a lightweight wrapper
around mach semaphores. The implementation is similar to
`dispatch_semaphore_t`, but allows better type safety with equal speed.

#### Example:
```
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

#### Multiplexing

Choosing from multiple channels can be done with the `select_chan()` function:

```
if let selection = select_chan(receiver1, receiver2, sender3)
{
  switch selection.id
  {
  case let s where s === receiver1: receiver1.extract(selection)
  case let s where s === receiver2: receiver2.extract(selection)
  case let s where s === sender3:   sender3.insert(selection, newElement)
  default: break // necessary to satisfy `switch`
  }
}
```

A timeout can be implemented with `select_chan()` and the `Timer` class, which
implements a timeout as a `Receiver`. `select_chan()` also has an option to prevent
blocking, enabling non-blocking attempts to receive or send on one or more channels.


#### Performance

On OS X, with Swift 2.0b1 and whole-module optimization,
message transmission with no thread contention about as fast as
in Go 1.4. With thread contention, Go channels are *much* faster (about 10x),
due to the context switching time involving threads. Go has a
very lightweight concurrency system, while this library must pause and
resume system threads.

When under contention, message transmission through an unbuffered channel
takes about the same time as two context switches, and that
is about as good as can be expected.

I welcome questions and suggestions.
