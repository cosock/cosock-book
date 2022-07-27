local cosock = require "cosock"

local Timer = {}
Timer.__index = Timer

function Timer.new(secs)
  return setmetatable({
    secs = secs,
    waker = nil,
  }, Timer)
end

function Timer:wait()
  coroutine.yield({self}, {}, self.secs)
end

function Timer:setwaker(kind, waker)
  print("setwaker", kind, waker)
  if waker then
    self.waker = function()
      print("waking up!")
      waker()
    end
  else
    self.waker = nil
  end
end

cosock.spawn(function()
  local t = Timer.new(2)
  print("waiting")
  t:wait()
  print("waited")
end)

cosock.run()
