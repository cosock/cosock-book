# Cosock

Cosock is a coroutine runtime written in pure Lua and based on the popular luasocket library.

The goal of the project is to provide the same interfaces that luasocket provides but wrapped
up in coroutines to allow for concurrent IO.

> Note: these docs will use the term coroutine, task, and thread interchangeably to all mean
> a [lua coroutine](https://www.lua.org/pil/9.html)

For example, the following 2 lua programs use luasocket to define a tcp client and server.

```lua
{{#include ../examples/client.lua}}
```

```lua
{{#include ../examples/server.lua}}
```

If you were to run `lua ./server.lua` first and then run `lua ./client.lua` you should see each terminal print out
their "sending ..." messages forever.

Using cosock, we can actually write the same thing as a single application.

<span id="clientserver-example"></span>

```lua
{{#include ../examples/client_server.lua}}
```

Now if we run this with `lua ./client_server.lua` we should see the messages alternate.

Notice that we called [`cosock.spawn`](~/02-spawn.html) twice, once for the server task and
once for the client task, we are going to dig into that next. We also added a call to `cosock.run`
at the bottom of our example, this function will run our tasks until there is no more work to do
so it is important you don't forget it or nothing will happen.
