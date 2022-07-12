
--- @class BoundedChannelSender
--- @field _link BoundedChannel
--- @field timeout number|nil A max timelimit to wait on sending
local BoundedChannelSender = {}
BoundedChannelSender.__index = BoundedChannelSender

---
--- @param shared_queue BoundedChannel
function BoundedChannelSender.new(shared_queue)
  return setmetatable({_link = shared_queue}, BoundedChannelSender)
end

--- Close this channel pair
function BoundedChannelSender:close()
  self._link:close()
  -- If anything is waiting to receieve it should wake up with an error
  self._link:try_wake("recvr")
end

--- Send a message to the BoundedChannelReceiver
--- @param msg any
function BoundedChannelSender:send(msg)
  while true do
    
    local can_send, err = self._link:can_send()
    if can_send then
      self._link:push_back(msg)
      -- Wake any receivers wo might be waiting to receive
      self._link:try_wake("recvr")
      return 1
    end
    if err == "closed" then
      return nil, "closed"
    end
    if err == "full" then
      local wake_t = {
        setwaker = function(t, kind, waker)
          assert(kind == "sendr")
          self._link:set_waker_sendr(t, waker)
        end
      }
      local _r, _s, err = coroutine.yield(nil, {wake_t}, self.timeout)
      if err then
        return nil, err
      end
    end
  end
end

--- Set the timeout for this sender
--- @param timeout number|nil
function BoundedChannelSender:settimeout(timeout)
  self.timeout = timeout
end

return BoundedChannelSender
