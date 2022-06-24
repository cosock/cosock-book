-- clients_server_select.lua
local cosock = require "cosock"
local socket = require "cosock.socket"
local ip = "0.0.0.0"

local number_of_clients = 10

--- Since the clients and server are in the same application
--- we can use an OS assigned port and share it across the
--- two tasks, to coordinate the two tasks to start in the order
--- we want, we can use a cosock channel to make sure both tasks
--- have the same port number
local port_tx, port_rx = cosock.channel.new()

--- Handle a client being ready to receive
--- @param client cosock.socket.tcp
--- @return integer|nil @1 if successful
--- @return nil|string @nil if successful, error message if not
function handle_recv(client, clients)
  local request, err = client:receive()
  if not request then
    if err == "closed" then
      clients[client] = nil
    end
    return
  end
  print(string.format("received %q", request))
  if request:match("ping") then
    print("sending pong")
    local s, err = client:send("pong\n")
    if err == "closed" then
      clients[client] = nil
    elseif err then
      print("error in recv: " .. tostring(err))
    end
  else
    client:close()
    clients[client] = nil
  end
end

--- Handle a server being ready to accept
--- @param server cosock.socket.tcp
--- @return cosock.socket.tcp|nil
--- @return nil|string @nil if successful, error message if not
function handle_accept(server, clients)
  local client, err = server:accept()
  if err and err ~= "timeout" then
    error("error in accept: " .. tostring(err))
  end
  if client then
    clients[client] = true
  end
end

--- Spawn a task for handling the server side of the socket
cosock.spawn(function()
  local server = socket.tcp()
  server:bind(ip, 0)
  local _ip, p = server:getsockname()
  port_tx:send(p)
  server:listen()
  local clients = {}
  server:settimeout(0)
  while true do
    local recvt = {}
    for client, _ in pairs(clients) do
      table.insert(recvt, client)
    end
    if #recvt < 5 then
      table.insert(recvt, server)
    end
    local recvr, _sendr, err = cosock.socket.select(recvt, {}, 5)
    if err == "timeout" then
      return
    elseif err then
      error("Error in select: "..tostring(err))
    end

    for _, sock in ipairs(recvr) do
      if sock == server then
        print("accepting new client")
        handle_accept(server, clients)
      elseif clients[sock] then
        handle_recv(sock, clients)
      end
    end
  end
end, "server task")

--- A single client task
---@param id integer The task's identifier
---@param port integer The server's port number
local function spawn_client(id, port)
  print("spawn_client", id, port)
  local client = socket.tcp()
  client:connect(ip, port)
  for _=1,10 do    
    print("sending ping", id)
    client:send(string.format("ping %s\n", id))
    local request = assert(client:receive())
    assert(request == "pong")
    socket.sleep(0.5)
  end
  client:close()
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
end, "clients task")

--- Finally we tell cosock to run all our coroutines until they are done
--- which should be forever
cosock.run()
