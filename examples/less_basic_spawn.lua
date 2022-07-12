--less_basic_spawn.lua
local cosock = require "cosock"

local function tick_task()
  while true do
    print(cosock.socket.gettime(), "tick")
    cosock.socket.sleep(2)
  end
end

local function tock_task()
  cosock.socket.sleep(1)
  while true do
    print(cosock.socket.gettime(), "tock")
    cosock.socket.sleep(2)
  end
end

cosock.spawn(tick_task, "tick-task")
cosock.spawn(tock_task, "tock-task")
cosock.run()
