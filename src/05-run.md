# Advanced Overview of `cosock.run`

## Global Variables

Cosock utilized a few global variables to allow for the potentially recursive nature of lua coroutines.

- `threads`: List of all coroutines cosock is aware of
  - This is populated by the first argument to `cosock.spawn`
- `threadnames`: A map of coroutine<->name pairs
  - This is populated by the second argument ot `cosock.spawn`
- `threadswaitingfor`: A map of coroutine<->select args
  - Select args have the type `{recvr: table<cosock.socket>, sendr: table<cosock.socket>, timeout: float?}`
  - This populated by the values provided to `coroutine.yield` for cosock tasks from a call to `cosock.socket.select`
- `readythreads`: A map of coroutine<->resume args that will be ready on the next pass
  - Resume args have the type `{recvr = table<cosock.socket>, sendr = table<cosock.socket>, err: string?}`
  - This is populated by coroutine wake-ups that occur on the current pass
- `socketwrappermap`: A map of luasocket<->cosock socket pairs
  - This map is keyed with the table pointer for the luasocket for easily getting back to a cosock socket when you
    only have a luasocket
  - This gets populated when a cosock socket is included in a select args table
- `threaderrorhandler`: Potential error handler function. Not currently settable.
- `timers`: [see Timers](#timers)
  
## Run Loop

To start the loop we define a few local variables. First up is `wakethreads`, This table will be
populated by removing all of the elements from `readythreads`, which frees up `readythreads` to
be added to by any tasks we are about to wake up. Next are the two list tables `sendt` and `recvt`
along with the optional integer `timeout`, these will end up being passed to luasocket's `socket.select`
when we run out of ready threads. Now we can move all our `readythreads` into `wakethreads` and then
loop over all of the ready threads.

For each ready thread, we first check if the `coroutine.status` for it is `"suspended"`, if it isn't we
will skip this thread. For any `"suspended"` thread, we first cancel any timers that might be scheduled
for that thread by calling `timers.cancel`. Next we pull out the values we stored in `threadswaitingfor`
and call `skt:setwaker` with `nil` for any `sendr` or `recvr` properties, this will prevent any potential
"double wakes" from occurring.

Now we call `coroutine.resume` with our `thread`, and the `recvr`, `sendr` and `err` values that were stored
in `wakethreads`. When `coroutine.resume` completes, we have 2 pieces of information that drive our next path.
The first return value from `coroutine.resume` will indicate if our `thread` raised an error or not, the second
is that we call `coroutine.status` on our `thread`. If our `thread`'s status is `"dead"` and `coroutine.resume`
returned `false`, something has gone terribly wrong so we raise an error (with a traceback if `debug` is available).
If our `thread`'s status is `"dead"` and `coroutine.resume` returned `true`, we just remove our `thread` from `threads`
and `threadswaitingfor`. If our `thread`'s status is `"suspended"` and `coroutine.resume` returned `true` then we first
update `threadswaitingfor` with the remaining return values from `coroutine.resume`. We also then call `skt:setwaker`
for any `sendr` and `recvr` in those values to a function that will clear itself and call the local function
`wake_thread`. At this point we also update our local tables `recvt` and `sendt`, to include the `skt.inner_sock`
values from `threadswaitingfor` which are the `luasocket`s associated with a `cosock.socket`.

Now that we have resumed all of the `wakethreads` and filled in our eventual arguments to `socket.select`, we then
determine if we are still `running`, we do this by looping over all of our `threads` and checking that at least 1 has
a `coroutine.status` that is not `"dead"`. If all `threads` are `"dead"` and nothing got added to `readythreads` then
we exit the run loop. Next we update our `socketwrappermap` by looping over all of the values in `threadswaitingfor`
and insert each `recvr` and `sendr` into the key of `skt.inner_sock`.

With all the bookkeeping done, we run all of the `timers` that have reached their deadline, and update our
local variable `timeout` to the duration until the shortest remaining timeout. If at least one thread was added to
`readythreads`, we set our timeout to 0, because we already know we have new work to do. At this point if `timeout` is
`nil` and both `sendt` and `recvt` are empty, we raise an error because we are about to call
`socket.select({}, {}, nil)` which would just block forever. At this point, we call `socket.select` capturing the
values in `recvr`, `sendr` and `err`. If `err` isn't the value `"timeout"`, we raise that error. If `err` is `nil`
or `"timeout"`, we loop over all of the values in `recvr` and `sendr`, looking up the cosock socket in
`socketwrappermap` and calling `skt:_wake` which would call the function we provided to `setwaker` above.

With that complete, we now have a fully updated `readythreads` and we start the loop again.

<details>
<summary>Outline Version</summary>

1. Define `wakethreads`
2. Define an empty list of senders (`sendt`), receivers (`recvt`) and a `timeout`
3. Pop all `readythreads` entries into the `wakethreads`
4. Loop over all threads in `wakethreads`
   1. If `coroutine.status` for that thread returns "suspended"
      1. Clear any timers
      2. Clear any wakers registered with a `timeout`
      3. `coroutine.resume` with the stored `recv4`, `sendr` and `err` arguments
      4. If `coroutine.resume` returned `true` in the first position and `coroutine.status` returns "suspended"
         1. Re-populate `threadswaitingfor[thread]` with the 3 other return values from `coroutine.resume`
            1. These should be the `recvt`, `sendt` and `timeout` values that will populate select args
         2. Set the waker for all sockets in `recvt` and `sendt` to call `wake_thread` and then unset themselves
         3. If `coroutine.resume` returned a `timeout`, create a new timer for this thread which will call `wake_thread_err` on expirations with the value "timeout"
      5. if `coroutine.status` returned "dead"
         1. If `coroutine.resume` returned `false` in the first position and no `threaderrorhandler` has been set
            1. Raise an error
               1. If the `debug` library is available, include a `debug.traceback` and the second return value from `cosock.resume`
               2. Else just raise an error with the second return value from `cosock.resume`
            2. Exit the application
               1. This calls `os.exit(-1)`
   2. Else, print a warning message if printing is turned on
5. Initialize a variable `running` to `false`
6. Loop over all `threads`, calling `coroutine.status` on each, if at least 1 doesn't return "dead", set `running` to `true`
7. If `running` is `false` and `readythreads` is empty
   1. Exit the run loop
8. Loop over all the values in `threadswaitingfor`
    1. Insert the luasockets on any `sendr` or `recvr` parameters to the loop local variables `sendt` and `recvt`
    2. Populate `socketwrappermap` with any `sendr` or `recvr`s
9. Call `timers.run`
10. If `readythreads` is not empty
    1. Set `timeout` to `0`
11. If `timeout` is falsy and `recvt` is empty and `sendt` is empty
    1. Raise an error that cosock.select was called with no sockets and no timeouts
12. Call luasocket's `socket.select` with our loops `recvt`, `sendt` and `timeout`
13. If `socket.select` returns a value in the 3rd position and that value is not `"timeout"`
    1. Raise an error with that return value
14. Loop over the `recvr` (1st) return from `socket.select`
    1. Look up the `cosock.socket` from `socketwrappermap`
    2. Call `skt:_wake("recvr")`
15. Loop over the `sendr` (2nd) return from `socket.select`
    1. Look up the `cosock.socket` from `socketwrappermap`
    2. Call `skt:_wake("sendr")`

</details>

## Timers

Internally, we keep a list of `timer` objects to determine when any `thread` would have reached the maximum time
it should be running/yielding for. We can interact with these through a module local variable `timers` which
has a few associated functions.

Inside of a `do` block, we create 2 local variables `timeouts` and `refs` for use in the `timer` associated functions.

The first associated function worth discussing is `timers.set`, which takes the arguments `timeout: float`,
`callback: fun()` and `ref: table`. When called, we first capture the current timestamp via `socket.gettime()`,
we then calculate the deadline for this timer by adding `timeout` to that timestamps into a variable `timeoutat`.
We then `table.insert` the the table `{ timeoutat = timeoutat, callback = callback, ref = ref }` into `timeouts`.
If `ref` isn't `nil` we also populate `refs[ref]` with that same table.

Next up is `timers.cancel` which takes the arguments `ref: table`. When called, we first lookup the timeout info
from `refs[ref]`, if we find something there we remove the values in the properties `callback` and `ref` and finally
we remove the value from `refs`. By removing the `callback` we avoid ever calling the consequence of that timer.
Eventually it will be removed from `timeouts` in the next call to `run`.

Finally we have `timers.run` this function takes no arguments. When called, it first sorts the `timeouts` table in
ascending order by `timeoutat`, where `nil` values are the smallest values. We then capture the current timestamp
by calling `socket.gettime`. Now we consult the first element of `timeouts`, if that table as a `timeoutat` of `nil`
or is less than now, we pop it off list, if it has a `callback` property we call that, if it has a `ref` property
we remove it from `refs`.

Now that all the pending timers are done, we use the new first element of `timeouts`' `timeoutat` property to calculate
the next relative timeout (`timeoutat - now`) and return that as the earliest timeout. If `timeouts` is empty, we return
`nil`.

<details>
<summary>Outline Version</summary>

- A timer has the shape `{timeoutat: float, callback: fun(), ref: table?}`
  - `timers.set`
    - Updates `timers` to include that value. Also updates a private scoped table named `refs`
      - `refs` is a map of table pointer<->timer which is used for cancellation of a timer
  - `timers.cancel`
    - If the provided table pointer is in `refs`, remove the `callback` and `ref` properties from that table
    - Set the table pointer key in `refs` to `nil`
  - `timers.run`
    - Sort all timeouts by deadline (earliest first)
    - Pop the timer off the front of the `timers` list
    - If that `timer.timeoutat` is `nil` or `< socket.gettime()`
      - Call `timer.callback`
      - remove this `timer` from `refs`
    - If there are any more timeouts left, return how long before that timeout should expire
    - If there are no more timeouts, return `nil`

</details>
