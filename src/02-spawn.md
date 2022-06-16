# Spawn

At the core of cosock's ability to work is the ability to wrap any operation in a coroutine and
register that with cosock. For this cosock exports the function `cosock.spawn`. This function takes
2 arguments, the first is a function that will be our coroutine, and the second is a name for that coroutine.

For example, this is a simple program that will spawn a single coroutine, which will print the current
timestamp and the word "tick" and then sleep for 1 second in a loop forever.

```lua
{{#include ../examples/basic_spawn.lua}}
```

The act of calling `cosock.spawn` allows us to use the non-blocking `cosock.socket.sleep` function. This means
we could extend our application to not only print this message every second but use the time this coroutine
is sleeping to perform some other work. Let's extend our little example a bit.

<<<<<<< HEAD
<span id="ticktock-example"></span>

=======
>>>>>>> spawn
```lua
{{#include ../examples/less_basic_spawn.lua}}
```

Very similar to our last example, this time we are spawning 2 coroutines one will print `"tick"` every two seconds
the other will wait 1 second and then print `"tock"` every two seconds. This should result in a line getting
printed to the terminal once a second alternating between our two strings. Notice though, there is a fair amount
of code duplication as `tick_task` and `tock_task` are nearly identical. This is mostly driven by the fact
that the first argument to `cosock.spawn` is a function that takes no arguments and returns no values which
means we can't ask cosock to pass in any arguments. One way we can get around this is by using
[closures](https://www.lua.org/pil/6.1.html). So instead of passing a function to
`cosock.spawn` we can _return_ a function from another function and use it as the argument to `cosock.spawn`.
For example:

```lua
{{#include ../examples/even_less_basic_spawn.lua}}
```

Notice here that `create_task` returns a function but takes a `name` argument and a `should_sleep_first`
argument which are available to our returned function.

Now, let's consider our [first example](~/../01-cosock.html#clientserver-example) which may not look like it
but is very similar to our tick/tock example.

Instead of using `cosock.socket.sleep` to tell cosock we are waiting around for something, it uses
the `receive` method on a `cosock.socket.tcp`. Let's break down what is happening in that example.

```text
   Server Task                  Cosock                   Client Task
  ┌────────────────────────────┬──────┬─────────────────────────────┐
  │                            │xxxxxx│                             │
  │                            │xxxxxx│                             │
  │                      resume│xxxxxx│resume                       │
  │◄───────────────────────────┤xxxxxx├────────────────────────────►│
  │                            │xxxxxx│                             │
  │server:bind                 │xxxxxx│              channel:receive│
  │server:getsockname          │xxxxxx│◄────────────────────────────┤
  │channel:send                │xxxxxx│                        yield│
  │server:accept               │xxxxxx│                             │
  ├───────────────────────────►│xxxxxx│resume with port             │
  │yield                       │xxxxxx├────────────────────────────►│
  │          resume with client│xxxxxx│               client:connect│
  │◄───────────────────────────┤xxxxxx│◄────────────────────────────┤
  │                            │xxxxxx│                        yield│
  │                            │xxxxxx│resume connected             │
**│****************************│xxxxxx├────────────────────────────►│
*L│client:receive              │xxxxxx│                             │
*O├───────────────────────────►│xxxxxx│*****************************│**
*O│yield                       │xxxxxx│                  client:send│L*
*P│            resume with ping│xxxxxx│               client:receive│O*
* │◄───────────────────────────┤xxxxxx│◄────────────────────────────┤O*
* │                            │xxxxxx│                        yield│P*
* │client:send                 │xxxxxx│resume with pong             │ *
**│****************************│xxxxxx├────────────────────────────►│ *
  │                            │xxxxxx│*****************************│**
  └────────────────────────────┴──────┴─────────────────────────────┘

```

To start, both tasks will be resumed which means that cosock has selected it to run, we can't say
for sure which task will get resumed first which is why we used a `cosock.channel` to make the
client task wait until the server was ready. Shortly after resuming, each task eventually calls
some method that will `yield` which means that it is waiting on _something_ so cosock can run
another task. For the server, the first time we `yield` is in a call to `accept`, if the client
hasn't already called `connect` we would end up blocking so instead of blocking, we let another
task work, when we finally have a client connected cosock will wake us back up again. On the
client-side we first `yield` on a call to `channel:receive`, if the server hasn't sent the port
number we would end up blocking that task from calling `bind` so we let the other task work until
we finally have a port number and then cosock will wake us back up.

This pattern continues, each task running exclusively until it needs to wait for something yielding
control back to cosock. When the thing we were waiting for is ready, we can continue running again.

In both our tick/tock examples and our client/server example, we reach a point where cosock is just
handing control from task 1 to task 2 and back again in an infinite loop. In a more real-world
program, you might see any number of tasks, that need to be juggled. In our next example, we will
extend the client/server example to handle any number of clients.

<span id="clientsserver-example"></span>

```lua
{{#include ../examples/clients_server.lua }}
```

Surprisingly little has changed. First, we updated the socket task to call `accept` more than once
and then pass the returned `client` into its own task to `receive`/`send` in a loop there.

For the client-side, we broke the client `send`/`receive` loop into its own task and added
a parent task to wait for the port number and then `cosock.spawn` a bunch of client tasks.

If you were to run this example, you would see that the print statements end up in random order!
