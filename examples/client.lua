--client.lua
local socket = require "socket"
local client = socket.tcp()
client:connect("0.0.0.0", 9999)
while true do
  print("sending ping")
  client:send("ping\n")
  local response = assert(client:receive())
  assert(response == "pong")
end
