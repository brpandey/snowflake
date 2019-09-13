#############

# Snowflake

A small distributed system in Elixir to assign unique numbers to each resource that is being managed. 
These ids are globally unique numbers. Each id is only be given out at most once. The ids are 64 bits long.

The service is composed of a set of nodes, each running one process serving ids. 

A caller will connect to one of the nodes (typically via load balancer like haproxy) 
and ask it for a globally unique id. 

There are a fixed number of nodes in the system, up to 1024. 
Each node has a numeric id, 0 <= id <= 1023 which is stored in a dets file locally on the host to
simulate multiple nodes. 

Each node knows its id at startup and that id never changes for the node.

We assume that any node will not receive more than 100,000 requests per second.

NOTE: The highest requests/sec that I was able to see using wrk and wrk2 with Logger essentially turned off and
max_keepalive connections set to 5M was around ~ 7k req/sec or ~ 220k req/30 secs

Here's an example run

1) Local node lookups only
```elixir
brpandey@butterfly:~/Workspace/github/snowflake$ wrk -t6 -c20 -d30s --latency http://127.0.0.1:5454/lunique
Running 30s test @ http://127.0.0.1:5454/lunique
  6 threads and 20 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     2.63ms    1.44ms  37.47ms   83.89%
    Req/Sec     1.18k   222.01     2.48k    75.56%
  Latency Distribution
     50%    2.52ms
     75%    3.16ms
     90%    3.73ms
     99%    7.94ms
  211378 requests in 30.02s, 41.16MB read
Requests/sec:   7042.33
Transfer/sec:      1.37MB
```
2) Local and peer node lookups
```elixir
brpandey@butterfly:~/Workspace/github/snowflake$ wrk -t6 -c20 -d30s --latency http://127.0.0.1:5454/dunique?target=random
Running 30s test @ http://127.0.0.1:5454/dunique?target=random
  6 threads and 20 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     6.17ms    2.07ms  26.58ms   71.49%
    Req/Sec   488.64     37.00   676.00     70.72%
  Latency Distribution
     50%    6.05ms
     75%    7.39ms
     90%    8.75ms
     99%   11.70ms
  87608 requests in 30.03s, 17.06MB read
Requests/sec:   2917.27
Transfer/sec:    581.71KB
```
3) Using a lua script which iterates through each of the worker nodes on a single machine
```elixir
brpandey@butterfly:~/Workspace/github/snowflake$ wrk -t6 -c30 -d30s -s run.lua --latency http://127.0.0.1:5454
Running 30s test @ http://127.0.0.1:5454
  6 threads and 30 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     4.71ms    3.53ms  52.22ms   74.90%
    Req/Sec     1.16k   422.22     2.35k    61.83%
  Latency Distribution
     50%    3.93ms
     75%    6.33ms
     90%    8.94ms
     99%   17.12ms
  206984 requests in 30.07s, 40.31MB read
Requests/sec:   6883.72
Transfer/sec:      1.34MB
```
NOTE: For wrk tests open 5 terminals, 1 for the wrk command and the other for each of the nodes

```elixir
brpandey@butterfly:~/Workspace/github/snowflake$ PORT=5454 elixir --name lookup_node1@127.0.0.1 -S mix run --no-halt
brpandey@butterfly:~/Workspace/github/snowflake$ PORT=5455 elixir --name lookup_node2@127.0.0.1 -S mix run --no-halt
brpandey@butterfly:~/Workspace/github/snowflake$ PORT=5456 elixir --name lookup_node3@127.0.0.1 -S mix run --no-halt
brpandey@butterfly:~/Workspace/github/snowflake$ PORT=5457 elixir --name lookup_node4@127.0.0.1 -S mix run --no-halt
```
A) Global uniqueness
The ids are guaranteed globally unique assuming the source of timestamps has millisecond sub millisecond precision,
as we prevent id collisions by appending node_ids (or worker_ids) and for same node id generations we monotonically
increment an atomic counter.  Should a node be deployed with multiple data centers either they should have different
node ids or we should add some data center bits to our id generation. This is discussed more in the Id module. (This is all within the custom epoch time)

B) Performance - 100,000 req/sec per node?
One node is able to hit a max of around 7k through various wrk tests.  Haven't tried the Tsung Erlang load test tool.
This was all done on a single dual-core Linux box vs some cloud instances
butterfly 4.15.0-58-generic #64-Ubuntu SMP Tue Aug 6 11:12:41 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
Definately room for more cores and optimizations

C) Failure cases
Uniqueness is still preserved after system fails and restarts and node crashes since it is centered around timestamps
Software defects are handled through exception handling and supervisors

Lastly, to run tests you may want to run MIX_ENV=test mix seed Feel free to blow away the priv/persis dir and rerun the mix seed custom task

Feel free to read the source code and comments.

Thanks! Bibek
