-- bad_news_channels.lua
local cosock = require "cosock"

local tx, rx = cosock.channel.new()

cosock.spawn(function()
  rx:receive()
  print("task 1")
end)

cosock.spawn(function()
  rx:receive()
  print("task 2")
end)

tx:send()

cosock.run()
