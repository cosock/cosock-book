# Internals

The module `cosock.socket.internals` is where luasocket gets wrapped into a "cosock aware"
table. Initially, a call to `passthroughbuilder` is used to create a "builder" function.
`passthroughbuilder` takes 2 arguments, `recvmethods` and `sendmethods` which are both
a table where the keys are a method name and the values are a set-like table of
error messages that it would be appropriate to `yield` for. A good example of one of these is
the `tcp` module's `recvmethods`.

```lua
local recvmethods = {
  receive = {timeout = true},
  accept = {timeout = true},
}
```
In both of the methods defined here, if we were to get the return value of `nil, "timeout"`
would be a signal to call `coroutine.yield` and try again. The return value of
`passthroughbuilder` is a function that we will call `builder`. `builder` takes 2 arguments
`method` which is a string and an optional `transformsrc` which is a table,
or a function that returns a table, with the following properties.

- `input`: this is an optional function that takes the method inputs and returns those inputs
           potentially transformed.
  - This is only called once, just before we call the luasocket method for the first time
- `blocked`: this is an optional function that takes the return values from the method called
             and returns the input arguments to the next call of the same method
- `output`: This is an optional function that will be called with the return values of the method
  - This is only called once, just before we return from the method

Let's use a few examples to go over each of these starting with the `input` property.

The method `receive` on a luasocket takes 2 arguments, a pattern string or number indicating
_how_ many bytes to try and read for and an optional prefix to put at the front of what was
received.


```lua
local socket = require "luasocket"
local t = socket.tcp()
t:connect("0.0.0.0", 8000)
print(t:receive("*l", "next line:"))
```

Assuming that some server is listening on port 8080 of the machine we run this on, we would
receive 1 line, for example, `"ping\n"` this would print `"next line: ping"`. As we will get
into later, a call to cosock's `receive` may end up calling luasocket's `receive`
until we get to a new line character. So what if our server sent 1 byte at a time? We would end
up printing `"next line: pnext line: inext line: nnext line: g"` if we passed the second argument
to the underlying luasocket. To avoid this we can use the `input` property to store this pattern
and only add it once to the eventual return value.

Now let's consider the `blocked` property, continuing to use `receive` as our example method,
what happens if we call `t:receive(10)` and again our server returns 1 byte at at time?

We can't call the underlying luasocket method with `10` over and over, that would result in us
requesting too many bytes from the socket. Instead, we need a way to capture the partial value
we received and reduce the number of bytes accordingly. Thankfully luasocket returns
any partial data on error as the 3rd return argument so we could do something like

```lua
{
  blocked = function(success, err, partial)
    table.insert(shared_buffer, partial)
    remaining_recv = remaining_recv - #partial
    return remaining_recv 
  end
}
```

This example assumes that `shared_buffer` and `remaining_recv` exist _somewhere_ but
you can see that we are appropriately reducing the number of bytes we return here. This
will eventually be the argument provided to the next call to the luasocket method.
Here is a longer-form example of how a response of 1 byte at a time would look for our
luasocket.

```lua
local shared_buffer = {}
local remaining_recv = 5
--p
local _, err, chunk = t:receive(remaining_recv)
remaining_recv = remaining_recv - #chunk
table.insert(shared_buffer, chunk)
--i
err, chunk = t:receive(remaining_recv) --i
remaining_recv = remaining_recv - #chunk
table.insert(shared_buffer, chunk)
--n
err, chunk = t:receive(remaining_recv) --n
remaining_recv = remaining_recv - #chunk
table.insert(shared_buffer, chunk)
--g
err, chunk = t:receive(remaining_recv) --g
remaining_recv = remaining_recv - #chunk
table.insert(shared_buffer, chunk)
--\n
err, chunk = t:receive(remaining_recv) --\n
remaining_recv = remaining_recv - #chunk
table.insert(shared_buffer, chunk)
```

Finally we have the `output` property which gets called with the last
return values from our method. If we complete our example, this is where
we would end up calling `table.concat(shared_buffer)` to add all
the chunks together before returning. 

Continuing to use `receive` as an example, this is what the transform
argument might look like.

```lua
local recvmethods = {
  receive = {timeout = true}
}
local sendmethods = {}
-- First we define a builder injecting the method<->error message maps
local builder = passthroughbuilder(recvmethods, sendmethods)
-- Now we can use the builder to define a method that doesn't do any
-- transformations
m.bind = builder("bind")
-- Here we define a method that performs some transformations
m.receive = builder("receive", function()
  local shared_buffer = {}
  local remaining_recv
  local pattern
  return {
    input = function(pat, prefix)
      -- insert the prefix as the first part of our return
      -- value if present
      if prefix then
        table.insert(shared_buffer, prefix)
      end
      if type(pat) == "number" then
        -- we know how many bytes to wait for, set this
        -- for use in blocked
        remaining_recv = pat
      else
        -- store this for use in blocked
        pattern = pat
      end
      -- return only pattern to avoid duplicate prefixes
      return pattern
    end,
    blocked = function(_, err, partial)
      if type(partial) == "string" and #partial > 0 then
        table.insert(shared_buffer, partial)
        -- only reduce remaining_recv if it is a number
        if remaining_recv then
          remaining_recv = remaining_recv - #full
          -- returning the updated remaining receive
          return remaining_recv
        end
        -- otherwise we return the pattern provided to input
        return pattern
      end
    end,
    output = function(full, err, partial)
      -- if the first return is a string with a length > 0 then
      -- add it to the buffer
      if type(full) == "string" and #full > 0 then
        table.insert(shared_buffer, full)
      end
      -- if the third return is a string with a length > 0 then
      -- add it to the buffer
      if type(partial) == "string" and #partial > 0 then
        table.insert(shared_buffer, partial)
      end
      -- concatenate all the strings together
      local all = table.concat(shared_buffer)
      if err then
        -- if ther was an error it should go in the 3rd return
        -- position
        return nil, err, all
      else
        -- if not error then it should go in the 1st return
        -- position
        return all
      end
    end
  }
end)
```

With the arguments defined, we can now discuss the return value of `builder`
which will be a third function, this one being
the method's implementation, its first argument is `self` and varargs
are used to allow for any additional arguments.

Let's pause here and go over this because 3 levels of functions can be
a bit difficult to follow. Our goal here is to re-use as much as possible
for each of the methods on a cosock socket and since yield -> retry loop is
going to be a common pattern we can define all of that in 1 place. The key is
that these methods are going to need to know about a few extra pieces which
is achieved by the fact that each function's arguments are available to the
returned function.

Which means that the `receive` method would have the following environment.

```lua
local recvmethods = {
  receive = { timeout = true }
}
local sendmethods = {}
local method = "receive"
local transformsrc = function() --[[see above]] end
```

Now let's go over what actually happens in this shared method implementation.
First, we capture all of the varargs into a table named `inputparams`,
if the transform object had an `input` property defined, we then overwrite
the variable with `{input(table.unpack(inputparams))}`. Now that we have our
inputs the way they need to be we begin a long-running `repeat`/`until`
loop.

At the top of the loop we call `self.inner_sock[method]`, `inner_sock` is
the property name for the luasocket on all of the cosock sockets. If the
first return from that function is `nil` we check to see if the second
return value can be found in `receivemethods` or `sendmethods`,
if so we know that we need to yield, so we check if `blocked`
is defined and call that if it is, again overwriting `inputparams`
with the return value.

Now we determine what `kind` of yield we are going to do, if the second
return was found in `receivemethods` it would be `"recvr"` if it was
found in `sendmethods` it would be `"sendr"`. Now we set up our arguments
for `coroutine.yield` putting `self` into `recvt` if our `kind` is `"recvr"`
or into `sendt` if our `kind` is `"sendr"`. Now we can call `coroutine.yield(sendt, recvt, self.timeout)` assigning the returns there to `recvr, sendr, rterr`. If `rterr` is not `nil`, we are going to return early, if its
value matches the error from our method call (i.e. "timeout" for both) then
we return the values from our call to that method.

The last thing we do in this case before heading back to the top of the loop
is to assert our kind and the result of `cosock.socket.select` match, meaning we have
a `kind` of `"sendr"`, the `sendr` variable is populated, and the `recvr` variable is unpopulated;
or vice versa.

----

If the first return argument to our method call was not `nil` then we
can exit early transforming the return value with `output` if that is
populated.
 
The only other function provided by `cosock.socket.internals` is
`setuprealsocketwaker` which completes the wrapping of our cosock socket.

This function takes the socket table and an optional list of `kinds`, if
`kinds` is not provided then the default will be both `sendr` and `recvr`.

We then define a method on `socket` called `setwaker` which is used
by cosock to wake up sleeping coroutines
([see the integrating chapter](./07-setwaker.md) for more info).
This `setwaker` will assign the provided `waker` function to
a `self.wakers` table based on the `kind` of `waker`. It also defines
a method `_wake` which takes an argument `kind` and varargs for any
additional arguments. This method will see if `self.wakers[kind]` is
not `nil` and if so call that with the varargs. It then replaces
`self.wakers[kind]` with `nil`.
