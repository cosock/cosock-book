-- clients_server.lua
local cosock = require "cosock"
local socket = require "cosock.socket"
local ip = "0.0.0.0"
local server = socket.tcp()

local number_of_clients = 10

--- Since the clients and server are in the same application
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
  while true do
    local client = server:accept()
    cosock.spawn(function()
      while true do
        local request = assert(client:receive())
        print(string.format("receieved %q", request))
        if request:match("ping") then
          print("sending pong")
          client:send("pong\n")
        else
          client:close()
          break
        end
      end
    end)
  end
end, "server task")

--- A single client task
---@param id integer The task's identifier
---@param port integer The server's port number
local function spawn_client(id, port)
  print("spawn_client", id, port)
  local client = socket.tcp()
  client:connect(ip, port)
  while true do    
    print("sending ping", id)
    client:send(string.format("ping %s\n", id))
    local request = assert(client:receive())
    assert(request == "pong")
    socket.sleep(0.5)
  end
end

--- Wait for the port from the server task and then
--- spawn the `number_of_clients` client tasks
local function spawn_clients()
  local port = assert(port_rx:receive())
  for i=1,number_of_clients do
    cosock.spawn(function()
      spawn_client(i, port)
    end, string.format("client-task-%s", i))
  end
end

--- Spawn a bunch of client tasks
cosock.spawn(function()
  spawn_clients()
end, "client task")

--- Finally we tell cosock to run all our coroutines until they are done
--- which should be forever
cosock.run()
