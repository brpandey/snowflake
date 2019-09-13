-- Checklist:
--
-- 1. Make sure to run mix seeds in the root directory
-- 2. Start four nodes in four terminals:
--    PORT=5454 elixir --name lookup_node1@127.0.0.1 -S mix run --no-halt
--    PORT=5455 elixir --name lookup_node2@127.0.0.1 -S mix run --no-halt
--    PORT=5456 elixir --name lookup_node3@127.0.0.1 -S mix run --no-halt
--    PORT=5457 elixir --name lookup_node4@127.0.0.1 -S mix run --no-halt
-- 3. In a separate shell, invoke wrk or wrk2 here's a few examples
--    wrk -t6 -c30 -d30s -s run.lua --latency http://127.0.0.1:5454
--    wrk2 -t6 -c30 -d30s -R100000 --latency http://127.0.0.1:5454/lunique
--    wrk -t6 -c30 -d30s --latency http://127.0.0.1:5454/lunique
--    wrk -t6 -c20 -d30s --latency http://127.0.0.1:5454/dunique?target=random

local counter = 0
local addrs   = {}

math.randomseed(os.time())



function setup(thread)
  local append = function(host, port)
    for i, addr in ipairs(wrk.lookup(host, port)) do
      if wrk.connect(addr) then
        addrs[#addrs+1] = addr
      end
    end
  end

  if #addrs == 0 then
    append("127.0.0.1", 5454)
    append("127.0.0.1", 5455)
    append("127.0.0.1", 5456)
    append("127.0.0.1", 5457)
  end

  local index = counter % #addrs + 1
  counter = counter + 1
  thread.addr = addrs[index]
end

request = function()
  wrk.method = "GET"
  path = "/lunique"
  return wrk.format(nil, path)
end
