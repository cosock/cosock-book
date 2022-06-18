--client_server_no_channel.lua
local cosock = require "cosock"
local socket = require "cosock.socket"
local ip = "0.0.0.0"
local server = socket.tcp()
local shared_port
--- Spawn a task for handling the server side of the socket
cosock.spawn(function()
  server:bind(ip, 0)
  local _ip, p = server:getsockname()
  shared_port = p
  server:listen()
  local client = server:accept()
  while true do
    local request = assert(client:receive())
    print(string.format("receieved %q", request))
    assert(request == "ping")
    print("sending pong")
    client:send("pong\n")
  end
end, "server task")

--- Spawn a task for handling the client side of the socket
cosock.spawn(function()
  --- wait for the server to be ready.
  while shared_port == nil do
    socket.sleep(1)
  end
  local client = socket.tcp()
  client:connect(ip, shared_port)
  while true do    
    print("sending ping")
    client:send("ping\n")
    local request = assert(client:receive())
    assert(request == "pong")
  end
end, "client task")

--- Finally we tell cosock to run our 2 coroutines until they are done
--- which should be forever
cosock.run()
