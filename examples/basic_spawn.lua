--basic_spawn.lua
local cosock = require "cosock"

cosock.spawn(function()
  while true do
    print(cosock.socket.gettime(), "tick")
    cosock.socket.sleep(1)
  end
end, "clock")
cosock.run()
