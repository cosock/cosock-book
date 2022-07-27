# Appendix A: Bounded Channel Limits

In our `BoundedChannelSender:send`, `BoundedChannel:set_waker_sendr` and
`BoundedChannel:try_wake` we have made some decisions that make our implementation a little easier
to read/write but might cause some problems if we end up depending on it.

To review, any time `BoundedChannelSender:send` would `yield` we create a temporary table
to handle our `setwaker` calls and in `BoundedChannel:set_waker_sendr`
we use that table as the key to `_wakers.sendr` to store/remove the `waker` function.

In `BoundedChannel:try_wake` we use the `next` function to choose which entry of `_wakers.sendr` to
call. The `next` function will always return the "first" key/value pair but what does that mean,
how can Lua tables be ordered? When a table is created, it is assigned a memory address, unique
to that table, we can see what the address is by using the default `__tostring` metamethod.

```sh
lua -e "print({})"
table: 0x5581bc0236a0
```

In the above, we can see the memory address of an empty table is `0x5581bc0236a0`, which will
change if we were to run it again. If we were to use this table as the key in another table that
table would look something like this.

```lua
{
  [0x5581bc0236a0] = "first element"
}
```
So, let's look at how Lua might order a table like this with more than one key.

<!-- Now that we have that outline, let's go over how this might negatively impact our send wakers.
The key issue here is that `next` will return the `waker` associated to the `wake_t` that has
the lowest memory address meaning we could potentially end up starving one of our senders if
our queue is full more than it is not. For example. -->

```lua
{{#include ../examples/table_key_order.lua}}
```

This example will create a table `tables` then loop 10 times assigning `tables[{}]` with `i`.
In a second loop to 10, we use the `next` function to pull the "first" key/value pair from
our `tables`. We then convert `t` by converting it into a hex string and then converting it
back into a number, which may be easier to read for some than trying to tell which hex value
is larger than another. It prints out the table representation and which `i` was assigned to it
then removes it from `tables` by assigning `tables[t]` with `nil`. If we run this once we might
see something like. 

```
93877018273488  1
93877018274240  9
93877018274016  7
93877018273792  5
93877018273616  3
93877018274352  10
93877018274128  8
93877018273904  6
93877018273680  4
93877018273552  2
```

At first, it looks like it might go in order because we get `1` but then we
see the second return from `next` is `9`. If we run it again we might see something like:


```sh
93837605766864  2
93837605767120  6
93837605767376  10
93837605766928  3
93837605767184  7
93837605766992  4
93837605767248  8
93837605766800  1
93837605767056  5
93837605767312  9
```

This time, we get `2` first and `9` last which means that we can expect the order to be somewhat
random. We can also see pretty obviously that Lua has ordered the keys by the lowest memory address
first. That means that `next` will return the `waker` associated to the `wake_t` that has
the lowest memory address. So what happens if one coroutine _always_ gets the lowest value?
It could starve other coroutines from being able to `send`.

This might not be all bad though, randomness can be good since we don't want to show a preference
and randomness does just that but that would require something like "a normalized distribution"
which would mean it would take a very long time to see the same order. Let's see how random our
temporary table keys are.

```lua
{{#include ../examples/table_key_order_a_lot.lua}}
```

Here we have extended our example to allow for repeating the creation of `tables` and then checking
to see if the new version matches any of the previous versions. We reduced the number of entries
to 9 to make it easier to read the results but otherwise, `get_set` will create the same table
as our original example. We have defined a table to hold all of our sets named `m` and defined a
method there `add_set` which will either return `nil` if the `set` argument isn't already in the
list or a results table if it was found. So what happens if we run this?

```text
RESULT
1       4
f,s
4,4
8,8
1,1
5,5
9,9
2,2
6,6
3,3
7,7
```

It looks like it only took us 3 sets to find the exact same order. Considering that 0-9 have
a potential number of combinations greater than 300,000 it seems that our distribution not very
normal.
