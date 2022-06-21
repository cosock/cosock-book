# Integrating with Cosock

So far we have covered what cosock provides but what if we want to integrate our
own libraries directly into cosock, what would that look like?

To start the general interface for a "cosock aware" lua table is to define a method `setwaker`
which takes 2 arguments, `kind: str` and `waker: fun()|nil`. The general idea here is
that a "waker" function can be provided that will get called when that task is ready
to be woken again.

Let's try and build an example `Timer` that will define this `setwaker` method to make
it "cosock aware"

```lua
{{#include ../examples/timer.lua}}
```

To start we create a lua meta-table `Timer`, which has the properties `secs: number` and
`waker: fun()|nil`. There is a constructor `Timer.new(secs)` which takes the number of
seconds we want to wait for. Finally, we define `Timer:wait` which is where our magic happens.
This method calls `coroutine.yield`, with 3 arguments `{self}`, an empty table, and `self.secs`.
These arguments match exactly what would be passed to `socket.select`, the first is a list of any
receivers, the second is a list of any senders and finally the timeout. Since we pass `{self}` as the
first argument that means we are treating `Timer` as a receiver. ultimately what we are doing here
is asking `cosock` to call `socket.select({self}, {}, self.secs)`. While we don't end up calling `self.waker`
ourselves, cosock uses `setwaker` to register tasks to be resumed so we need to conform to that. Just to
illustrate that is happening, a `print` statement has been added to `setwaker`, if we run this
we would see something like the following.

```shell
waiting
setwaker        recvr   function: 0x5645e6410770
setwaker        recvr   nil
waited
```

We can see that cosock calls `setwaker` once with a function and a second time with `nil`. Notice though
that `self.waker` never actually gets called, since we don't see a `"waking up"` message. That
is because we don't really _need_ to be woken up, our timer yields the whole coroutine until
we have waited for `self.secs`, nothing can interrupt that. Let's extend our `Timer` to have a reason
to call `self.waker`, we can do that by adding the ability to cancel a `Timer`.

```lua
{{#include ../examples/timer_with_cancel.lua}}
```

In this example, we create our timer that will wait 10 seconds but before we call `wait` we
spawn a new task that will sleep for 3 seconds and then call `cancel`. If we look over the
changes made to `wait` we can see that we still call `coroutine.yield({self}, {}, self.secs)`
but this time we are assigning its result to `r, s, err`. Cosock calls `coroutine.resume`
with the same return values we would get from `select`, that is a list of ready receivers,
a list of ready senders, and an optional error string. If the timer expires, we would expect
to get back `nil, nil, "timeout"`, if someone calls the `waker` before our timer expires
we would expect to get back `{self}, {}, nil`. This means we can treat any `err == "timeout"`
as a normal timer expiration but if `err ~= "timeout"` then we can safely assume our timer was canceled.
If we were to run this code we would see something like the following.

```shell
waiting
setwaker        recvr   function: 0x556d39beb6d0
waking up!
setwaker        recvr   nil
setwaker        recvr   nil
waited  3.0     nil     cancelled
```

Notice we only slept for 3 seconds instead of 10, and `wait` returned `nil, "cancelled"`!
One thing we can take away from this new example is that the waker API is designed to allow
one coroutine to signal cosock that another coroutine is ready to wake up. With that in mind,
let's try and build something a little more useful, a version of the
`cosock.channel` api that allows for a maximum queue size. Looking over the
[existing channels](https://github.com/cosock/cosock/blob/8388c8ebcf5810be2978ec18c36c3561eedb5ea8/cosock/channel.lua),
to implement this we are going to need to have 3 parts. A shared table for queueing and
setting the appropriate wakers, a receiver table and a sender table. Let's start by
defining the shared table.
