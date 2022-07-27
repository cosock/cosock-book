local cosock = require "cosock"
local BoundedChannel = require "examples.bounded_channel"

local tx, rx = BoundedChannel.new(2)

cosock.spawn(function()
  local s = cosock.socket.gettime()
  for i=1,10 do
    tx:send(i)
    local e = cosock.socket.gettime()
    print(string.format("sent %s in %.1fs", i, e - s))
    s = e
    cosock.socket.sleep(0.2)
  end
end, "sendr1")

cosock.spawn(function()
  local s = cosock.socket.gettime()
  for i=11,20 do
    tx:send(i)
    local e = cosock.socket.gettime()
    print(string.format("sent %s in %.1fs", i, e - s))
    s = e
    cosock.socket.sleep(0.2)
  end
end, "sendr2")

cosock.spawn(function()
  local s = cosock.socket.gettime()
  for i=1,20 do
    local msg = rx:receive()
    local e = cosock.socket.gettime()
    print(string.format("recd %s in %.1fs", msg, e - s))
    s = e
    cosock.socket.sleep(1)
  end
end, "recvr")

cosock.run()
