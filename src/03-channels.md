# Channels

Coordinating coroutines can be a huge pain, to ease this pain cosock offers a synchronization primitive
called channels. A `cosock.channel` is a "multiple producer single consumer" message queue, this means you can
have one coroutine own the receiving half of the queue and pass the sender out to however many
coroutines you'd like. We've already seen how they are used, in our
[first example](01-cosock.md#clientserver-example), we used a `cosock.channel` to coordinate which port
the client should `connect` to. What if we wanted to re-write that example without using a channel, that might look
something like this: 

```lua
{{#include ../examples/client_server_no_channel.lua}}
```
That update removed our channel in favor of polling that `shared_port ~= nil` once every second. This will
absolutely work, however, we have introduced a race condition. What if we sleep for 1 full second _right before_
the server is issued its port? That second would be wasted, we could have already been creating our client. 
While the consequence in this example isn't dire, it does show that relying on shared mutable state without
some way to synchronize it between tasks can be problematic. 

> As a note, we could also solve this problem by having the server task spawn the client task but that wouldn't
> be nearly as interesting to our current subject.

Another place we have seen that could benefit from a channel is our [tick/tock example](02-spawn.md#ticktock-example),
in that example, we hard-coded the synchronization. The first task would print then sleep for 2 seconds and the second
task would sleep for 1 second and _then_ print and sleep for 2 seconds. Let's take a look at what that might have
looked like if we had used channels.

```lua
{{#include ../examples/tick_tock_channels.lua}}
```

In this version, we only have one definition for a task, looping forever, it will first wait to `receive` the signal,
and then it prints its name, sleeps for 1 second and then sends the signal on to the next task. The key to 
making this all work is that we need to kick the process off by telling one of the tasks to start. Since a
channel allows for multiple senders, it is ok that we call `send` in more than one place.

Now say we wanted to extend our little clock emulator to print `"clack"` every 60 seconds to simulate the
minute hand moving. That might look something like this:

```lua
{{#include ../examples/tick_tock_clack.lua}}
```

Here we have updated the tasks to now share a counter across our channel. So at the 
start of each loop iteration, we first get the current count from our other task. We again print our name
and then sleep for 1 second but now if the count is >= 59 we send the count of 0 to our `"clack"` task which
will always then send a 1 to the `"tick"` task to start the whole process over again. Just to make sure it
is clear, we can use the send half of the `"tick"` task's channel in 3 places, the main thread
to "prime" the clock, the `"tock"` task and the `"clack"` task.

It is very important that we don't try and use the receiving half of a channel in more than one
task, that would lead to potentially unexpected behavior. Let's look at an example of how that might
go wrong.

```lua
{{#include ../examples/bad_news_channels.lua}}
```

In this example, we create one channel pair and spawn two tasks which both call `receive` on our
channel and just before `run` we call `send`.  Since the choice for which task
should run at which time is left entirely up to cosock, we can't say for sure which of these tasks
will actually receive. It might print "task 1" then "task 2" or it might print them in the reverse. 

> In actuality, cosock assumes that `receive` will only ever be called from the same coroutine.
> Calling `receive` in multiple coroutines will (eventually) raise in a error.
