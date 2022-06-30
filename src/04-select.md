# Select

Now that we have covered how to spawn and run coroutines using cosock, let's talk about how we
could handle multiple IO sources in a single coroutine. For this kind of work, cosock provides
`cosock.socket.select`, this function works in a very similar way to luasocket's `socket.select`,
to call it would look something like `local recvr, sendr, err = cosock.socket.select(recvt, sendt, timeout)`
its arguments are

- `recvt`: This is a list of cosock sockets that are waiting to be ready to `receive`
- `sendt`: This is a list of cosock sockets that are waiting to be ready to `send`
- `timeout`: This is the maximum amount of seconds to wait for one or more entries in `recvt` or `sendt` to be ready
  - If this value is `nil` or negative it will treat the timeout as infinity

> Note: The list entries for `sendt` and `recvt` can be other "cosock aware" tables like the
> [lustre WebSocket](https://github.com/cosock/lustre), for specifics on how to make a table "cosock aware" 
> [see the chapter on it](07-setwaker.md)

Its return values are

- `recvr`: A list of ready receivers, any entry here should be free to call `receive` and
           immediately be ready
- `sendr`: A list of ready senders, any entry here should be free to call `send` and immediately be
           ready
- `err`: If this value is not `nil` it represents an error message
  - The most common error message here would be `"timeout"` if the `timeout` argument provided
    is not `nil` and positive

So, how would we use something like this? Let's consider our `clients_server.lua` example
from the [spawn chapter](./02-spawn.md), where we called `cosock.spawn` every time a new
client was `accept`ed, this works but we don't have much control over how many tasks we end
up spawning. In large part, this is because we don't know how long each task will run. To achieve
this, we would need to be able to handle all of the client connections on the same task as the
server and to do that, we can use `select`.

```lua
{{ #include ../examples/clients_server_select.lua }}
```

The above is an updated version of our
[clients/server example](./02-spawn.md#clientsserver-example) with some updates to limit
the total number of connections to 5, let's go over the changes.

First, we've added a few helper functions to handle the different events in our system,
the first is for when a client connection is ready to receive `handle_recv` takes 2 arguments,
`client` which is a `cosock.socket.tcp` that was returned from a call
to `accept` and `clients` which is a table where the keys are `cosock.socket.tcp` clients
and the values are `true`. We first call `client:receive` to get the bytes from
the client and if that returns a string that contains `"ping"` then we send our
`"pong"` message. There are few places where this can go wrong, the call to `receive`
could return `nil` and an error message or not `"ping"` or the call to `send` could
return `nil` and an error message; if the error message is `"closed"` or the request
didn't contain `"ping"` then we want to remove `client` from `clients` and if it was
the latter then we want to call `client:close`.

Next up we have `handle_accept` this also takes 2 arguments `server` which is a 
`cosock.socket.tcp` socket that is listening and the same map of `clients`. If a
call to `accept` returns a `client` then we add that `client` into our `clients` map.
If `accept` returns `nil` and `err` isn't `"timeout"` then we raise an error.

Alright, with these two helper functions we can now update the `"server"` task to
handle all of the connected clients w/o having to call `spawn`. Our tasks starts
out the same as before, creating a `server` socket, binding it to a random port,
gets that port and sends it to our `"clients task"` and then calls `listen`.
At this point, things start to change, first we define our `clients` map as
empty we then use `handle_accept` to accept the first connection and then call
`server:settimeout(0)` to avoid a potential server that will yield forever. 

Inside of our long-running loop, we start out by defining a new table `recvt` which
will match the argument to `select` which has the same name. We then loop over our
`clients` table, inserting any of the keys into `recvt`. We keep these as separate
tables because we want to be able to remove a `client` from our readiness check
once it has closed. Next, we check to see how large `recvt` is, if it is below 5
we add `server` into it. By only including `server` when `recvt` has fewer than
5 clients we have enforced our max connections limit.

With `recvt` defined we can finally call `cosock.socket.select`, we use `recvt` as
the first argument, an empty table as the `sendt` argument and finally a timeout of 5 seconds.
We assign the result of `select` into `recvr, _sendr, err`, we would expect that
`recvr` would contain any of our `clients` that are ready to `receive` and, if
we are below the limit, `server`. If `recvr` is `nil` we would expect `err` to be
the string describing that error. If `err` is `"timeout"` then we exit our server
task which should exit the application. If we don't have an `err` then we loop over
all the `recvr`s and check to see if they are our `server`, if so we call
`handle_accept` if not then we call `handle_recv`. Each of our helpers will update
the `clients` map to ensure that we service all of the client requests before exiting.

The last change we've made is to `spawn_client` which previously would loop forever,
it now loops 10 times before exiting and closing the `client`.

If we were to run this you would see each of the tasks spawn in a random order and
the first 5 of those would begin sending their `"ping"` messages. Once 1 of them
completes, we would accept the next connection but not before that point which means
we have limited our total number of connected clients to 5!
