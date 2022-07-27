--even_less_basic_spawn.lua
local cosock = require "cosock"

local function create_task(name, should_sleep_first)
  return function()
    if should_sleep_first then
      cosock.socket.sleep(1)
    end
    while true do
      print(cosock.socket.gettime(), name)
      cosock.socket.sleep(2)
    end
  end
end

cosock.spawn(create_task("tick", false), "tick-task")
cosock.spawn(create_task("tock", true), "tock-task")
cosock.run()
