--server.lua
local socket = require "socket"
local server = socket.tcp()
server:bind("0.0.0.0", 9999)
server:listen()
print("listening", server:getsockname())
local client = server:accept()
while true do    
  local request = assert(client:receive())
  assert(request == "ping")
  print("sending pong")
  client:send("pong\n")
end
