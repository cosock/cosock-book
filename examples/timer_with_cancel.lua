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
  local r, s, err = coroutine.yield({self}, {}, self.secs)
  if err == "timeout" then
    return 1
  end
  return nil, "cancelled"
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

function Timer:cancel()
  if self.waker then
    self.waker()
  end
end

cosock.spawn(function()
  local t = Timer.new(10)
  cosock.spawn(function()
    cosock.socket.sleep(3)
    t:cancel()
  end)
  print("waiting")
  local s = os.time()
  local success, err = t:wait()
  local e = os.time()
  print("waited", os.difftime(e, s), success, err)
end)

cosock.run()
