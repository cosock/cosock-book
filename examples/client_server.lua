-- client_server.lua
local cosock = require "cosock"
local socket = require "cosock.socket"
local ip = "0.0.0.0"
local server = socket.tcp()
--- Since the client and server are in the same application
--- we can use an OS assigned port and share it across the
--- two tasks, to coordinate the two tasks to start in the order
--- we want, we can use a cosock channel to make sure both tasks
--- have the same port number
local port_tx, port_rx = cosock.channel.new()

--- Spawn a task for handling the server side of the socket
cosock.spawn(function()
  server:bind(ip, 0)
  local _ip, p = server:getsockname()
  port_tx:send(p)
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
  local port = assert(port_rx:receive())
  local client = socket.tcp()
  client:connect(ip, port)
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
