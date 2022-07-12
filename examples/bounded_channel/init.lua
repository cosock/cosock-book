local BoundedChannelSender = require "examples.bounded_channel.sendr"
local BoundedChannelReceiver = require "examples.bounded_channel.recvr"

---@class BoundedChannel
--- This is the shared table that coordinates messages from one side of the
--- channel to the other. 
---@field _wakers {recvr: fun()?, sendr: fun()?} The two potential wakers
---@field _msg_queue table The pending messages
---@field _closed boolean If the channel has been closed
---@field _max_depth integer The max size of the channel
local BoundedChannel = {}
BoundedChannel.__index = BoundedChannel


--- Create a new channel pair
--- @return BoundedChannelSender
--- @return BoundedChannelReceiver
function BoundedChannel.new(max_depth)
  local link = setmetatable({
    _max_depth = max_depth,
    _wakers = {
      sendr = {},
    },
    _msg_queue = {},
    _closed = false,
  }, BoundedChannel)
  return BoundedChannelSender.new(link), BoundedChannelReceiver.new(link)
end

--- Remove the first element from this channel
function BoundedChannel:pop_front()
  return table.remove(self._msg_queue, 1)
end

--- Add a new element to the back of this channel
function BoundedChannel:push_back(ele)
  table.insert(self._msg_queue, ele)
end

function BoundedChannel:set_waker_sendr(sendr, waker)
  self._wakers.sendr[sendr] = waker
end


--- Set one of the wakers for this BoundedChannel
--- @param waker fun()|nil
function BoundedChannel:set_waker_recvr(waker)
  self._wakers.recvr = waker
  if waker and self:can_recv() then
    -- Check if receiving is currently available, if
    -- so call the waker to wake up the yielded receiver
    waker()
  end
end

--- If `self._wakers[kind]` is not `nil`, call it
function BoundedChannel:try_wake(kind)
  local waker
  if kind == "sendr" then
    _, waker = next(self._wakers.sendr)
  else
    waker = self._wakers.recvr
  end
  if type(waker) == "function" then
    waker()
  end
end

--- Check if sending is currently available, that means we are not closed
--- and the queue size hasn't been reached
---@return number|nil @if 1, we can send if `nil` consult return 2
---@return string|nil @if not `nil` either "closed" or "full"
function BoundedChannel:can_send()
  if self._closed then
    -- Check first that we are not closed, if we are
    -- return an error message
    return nil, "closed"
  end
  if #self._msg_queue >= self._max_depth then
    -- Check next if our queue is full, if it is
    -- return an error message
    return nil, "full"
  end
  -- The queue is not full and we are not closed, return 1
  return 1
end

--- Check if receiving is currently available, that means we are not closed
--- and the queue has at least 1 message
---@return number|nil @if 1, receiving is currently available if `nil` consult return 2
---@return string|nil @if not `nil` either "closed" or "empty"
function BoundedChannel:can_recv()
  if self._closed and #self._msg_queue == 0 then
    -- Check first that we haven't closed, if so
    -- return an error message
    return nil, "closed"
  end
  if #self._msg_queue == 0 then
    -- Check next that we have at least 1 message,
    -- if not, return an error message
    return nil, "empty"
  end
  -- We are not closed and we have at least 1 pending message, return 1
  return 1
end

--- Close this channel
function BoundedChannel:close()
  self._closed = true
end

return BoundedChannel
