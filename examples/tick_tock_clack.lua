--tick_tock_clack.lua
local cosock = require "cosock"

-- We create 2 pairs of channels so our two task can send messages
-- back and forth
local tick_tx, tick_rx = cosock.channel.new()
local tock_tx, tock_rx = cosock.channel.new()
local clack_tx, clack_rx = cosock.channel.new()

local function task(tx, rx, name)
  while true do
    -- First wait for the other task to tell us the count
    local count =  rx:receive()
    -- print our name
    print(cosock.socket.gettime(), name)
    -- sleep for 1 second
    cosock.socket.sleep(1)
    -- tell the other task we are done
    if count >= 59 then
      clack_tx:send(0)
    else 
      tx:send(count + 1)
    end
  end
end
-- spawn the task to print tick every two seconds
cosock.spawn(function()
  task(tock_tx, tick_rx, "tick")
end)
-- spawn the task to print tock every 2 seconds
cosock.spawn(function()
  task(tick_tx, tock_rx, "tock")
end)
cosock.spawn(function()
  task(tick_tx, clack_rx, "clack")
end)
-- prime the tick task tp start first
tick_tx:send(1)

cosock.run()
