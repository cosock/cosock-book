# Channels

Since global variables can be a huge pain to work with across coroutines. Cosock offers a synchronization primitive
called channels. This is a multiple producer single consumer message queue, this means you can have one coroutine own
the receiving half of the queue and pass the sender out to however many coroutines you'd like.

```lua
--TODO: provide example
```
