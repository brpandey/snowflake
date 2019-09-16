# [Snowflake](https://blog.twitter.com/engineering/en_us/a/2010/announcing-snowflake.html)

A small distributed system in Elixir to assign unique numbers to each resource that is being managed. 
These ids are 64 bit globally unique numbers given out at most once.

The service is composed of a set of nodes, each running one process serving ids. 

A caller will connect to one of the nodes (typically via load balancer like haproxy) 
and ask it for a globally unique id. 

There are a fixed number of nodes in the system, up to 1024. 
Each node has a numeric id, 0 <= id <= 1023 which is stored in a dets file locally on the host to
simulate multiple nodes. 

Each node knows its id at startup and that id never changes for the node unless explicitly removed via deleting the priv/persist directory.

We assume that any node will not receive more than 100,000 requests per second.

NOTE: The highest requests/sec that I was able to see using wrk and wrk2 with Logger essentially turned off and
max_keepalive connections set to 5M was around ~ 26k req/sec or ~ 800k req/30 secs.  I have added explicit coordination in the form
of a peer lookup for load distribution purposes triggered only via the /dunique path and also to illustrate node and cluster resiliency. The 
unique id generation itself does not rely on any distributed coordination other than a node_id read upon startup :)

```elixir
asdf install erlang 22.0.7
asdf global erlang 22.0.7
asdf install elixir 1.9.1
asdf global elixir 1.9.1
```

Here's an example run

1) Local node lookups only
```elixir
$ wrk -t6 -c30 -d30s --latency http://127.0.0.1:5454/lunique
Running 30s test @ http://127.0.0.1:5454/lunique
  6 threads and 30 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.22ms    1.01ms  41.49ms   96.55%
    Req/Sec     4.40k     1.42k   12.06k    73.68%
  Latency Distribution
     50%    1.12ms
     75%    1.42ms
     90%    1.72ms
     99%    5.07ms
  788618 requests in 30.10s, 153.43MB read
Requests/sec:  26200.53
Transfer/sec:      5.10MB
```
2) Local and peer node lookups
```elixir
$  wrk -t6 -c30 -d30s --latency http://127.0.0.1:5454/dunique?target=random
Running 30s test @ http://127.0.0.1:5454/dunique?target=random
  6 threads and 30 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     3.29ms    2.71ms  40.79ms   81.27%
    Req/Sec     1.72k   526.28     3.07k    71.11%
  Latency Distribution
     50%    2.60ms
     75%    4.35ms
     90%    6.63ms
     99%   13.15ms
  307555 requests in 30.04s, 59.83MB read
Requests/sec:  10236.57
Transfer/sec:      1.99MB
```
3) Using a lua script which utilizes each of the worker nodes on a single machine
```elixir
$ wrk -t6 -c30 -d30s -s run.lua --latency http://127.0.0.1:5454
Running 30s test @ http://127.0.0.1:5454
  6 threads and 30 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     2.80ms    4.64ms 102.79ms   90.16%
    Req/Sec     3.39k     1.31k    9.42k    77.35%
  Latency Distribution
     50%    0.99ms
     75%    3.01ms
     90%    7.35ms
     99%   21.42ms
  607150 requests in 30.08s, 118.12MB read
Requests/sec:  20187.59
Transfer/sec:      3.93MB
```
NOTE: For wrk tests open 5 terminals, 1 for the wrk command and the other for each of the nodes

```elixir
$ PORT=5454 elixir --name lookup_node1@127.0.0.1 -S mix run --no-halt
$ PORT=5455 elixir --name lookup_node2@127.0.0.1 -S mix run --no-halt
$ PORT=5456 elixir --name lookup_node3@127.0.0.1 -S mix run --no-halt
$ PORT=5457 elixir --name lookup_node4@127.0.0.1 -S mix run --no-halt
```
A) Global uniqueness
The ids are guaranteed globally unique assuming the source of timestamps has millisecond / sub millisecond precision,
as we prevent id collisions by appending node_ids (or worker_ids) given a cluster. For id generations on the same node, we monotonically
increment an atomic counter.  Should a node be deployed to multiple data centers either they should have different
node ids or we should add some data center bits to our id generation. This is discussed more in the Id module. (This is all within the custom epoch time)

Property testing can also be used to further verify uniqueness

B) Performance - 100,000 req/sec per node?
One node is able to hit a max of around 25k requests through various wrk tests.  Haven't tried the Tsung Erlang load test tool.

This was all done on a quad-core Linux box vs a cluster of cloud instances

```elixir
$ cat  /proc/cpuinfo
model name	: Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz
cpu MHz		: 983.461
cache size	: 6144 KB
siblings	: 8
cpu cores	: 4
```

C) Failure cases
Uniqueness is still preserved after system fails and restarts and node crashes since it is centered around timestamps
Software defects are handled through exception handling and supervisors and let it crash :)

Lastly, to run tests you may want to run the custom mix task and the Erlang port mapper daemon

```elixir 
$ MIX_ENV=test mix seed 
$ epmd -daemon 
```

Feel free to blow away the priv/persist dir and rerun the mix seed custom task

Feel free to read the source code and comments.


PS.  Here's output from one of the tests that partitions a cluster and then heals a cluster

```elixir
$ mix test test/node_test.exs:22
Compiling 9 files (.ex)
Generated snowflake app

13:38:12.516 [debug] Starting snowflake server
Excluding tags: [:test]
Including tags: [line: "22"]


13:38:13.239 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:13.887 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:14.507 [debug] Re-syncing node list after 10 seconds to make sure we have all the connected nodes

13:38:14.507 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:14.507 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:14.507 [debug] Resynced state of keys is #MapSet<["key00", "key01", "key02"]>

13:38:14.527 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:15.166 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:16.129 [debug] From :"lookup_node3@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:16.134 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:16.134 [debug] From :"lookup_node2@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:16.136 [debug] From :"lookup_node1@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:16.199 [debug] Starting snowflake server

13:38:16.200 [debug] Starting snowflake server

13:38:16.202 [debug] Starting snowflake server

13:38:16.207 [debug] Starting snowflake server

13:38:16.264 [debug] Setting canonical node list nodes [:"manager@127.0.0.1", :"lookup_node1@127.0.0.1", :"lookup_node2@127.0.0.1", :"lookup_node3@127.0.0.1", :"lookup_node4@127.0.0.1"]

13:38:16.264 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:16.264 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:16.264 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:16.264 [debug] From :"manager@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:18.145 [debug] Re-syncing node list after 10 seconds to make sure we have all the connected nodes

13:38:18.145 [debug] From :"lookup_node3@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:18.149 [debug] Re-syncing node list after 10 seconds to make sure we have all the connected nodes

13:38:18.149 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:18.150 [debug] Re-syncing node list after 10 seconds to make sure we have all the connected nodes

13:38:18.149 [debug] Re-syncing node list after 10 seconds to make sure we have all the connected nodes

13:38:18.150 [debug] From :"lookup_node1@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:18.150 [debug] From :"lookup_node2@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:18.150 [debug] From :"lookup_node3@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:18.152 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:18.152 [debug] From :"lookup_node1@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:18.152 [debug] From :"lookup_node2@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:18.153 [debug] From :"lookup_node3@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:18.154 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:18.154 [debug] From :"lookup_node1@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:18.154 [debug] From :"lookup_node2@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:18.174 [debug] Resynced state of keys is #MapSet<["key00", "key01", "key02", "key03", "key04"]>

13:38:18.174 [debug] Resynced state of keys is #MapSet<["key00", "key01", "key02", "key03", "key04"]>

13:38:18.175 [debug] Resynced state of keys is #MapSet<["key00", "key01", "key02", "key03", "key04"]>

13:38:18.176 [debug] Resynced state of keys is #MapSet<["key00", "key01", "key02", "key03", "key04"]>

13:38:18.265 [info]  1 About to partition

13:38:18.327 [debug] From :"lookup_node1@127.0.0.1", removing node :"lookup_node4@127.0.0.1"

13:38:18.327 [debug] From :"lookup_node4@127.0.0.1", removing node :"lookup_node1@127.0.0.1"

13:38:18.328 [debug] From :"lookup_node2@127.0.0.1", removing node :"lookup_node4@127.0.0.1"

13:38:18.329 [debug] From :"lookup_node3@127.0.0.1", removing node :"lookup_node4@127.0.0.1"

13:38:18.333 [debug] From :"lookup_node4@127.0.0.1", removing node :"lookup_node2@127.0.0.1"

13:38:18.334 [debug] From :"lookup_node4@127.0.0.1", removing node :"lookup_node3@127.0.0.1"

13:38:18.782 [error] ** Connection attempt from disallowed node :"lookup_node3@127.0.0.1" ** 


13:38:18.782 [warn]  [libcluster:chat] unable to connect to :"lookup_node4@127.0.0.1"

13:38:18.782 [error] ** Connection attempt from disallowed node :"lookup_node1@127.0.0.1" ** 


13:38:18.782 [error] ** Connection attempt from disallowed node :"lookup_node2@127.0.0.1" ** 


13:38:18.783 [warn]  [libcluster:chat] unable to connect to :"lookup_node4@127.0.0.1"

13:38:18.782 [warn]  [libcluster:chat] unable to connect to :"lookup_node4@127.0.0.1"

13:38:19.432 [error] ** Connection attempt from disallowed node :"lookup_node4@127.0.0.1" ** 


13:38:19.432 [warn]  [libcluster:chat] unable to connect to :"lookup_node3@127.0.0.1"

13:38:19.682 [error] ** Connection attempt from disallowed node :"lookup_node4@127.0.0.1" ** 


13:38:19.683 [warn]  [libcluster:chat] unable to connect to :"lookup_node1@127.0.0.1"

13:38:20.168 [error] ** Connection attempt from disallowed node :"lookup_node4@127.0.0.1" ** 


13:38:20.168 [warn]  [libcluster:chat] unable to connect to :"lookup_node2@127.0.0.1"

13:38:20.330 [info]  2 Partitioned n4 from rest of cluster

13:38:20.333 [debug] In cluster, get_node current node is :"manager@127.0.0.1" -- about to get node given CHOSEN key: key0, key state is #MapSet<["key00", "key01", "key02", "key03", "key04"]>, hash ring is %ExHashRing.HashRing{items: {{17825517198445669, :"lookup_node4@127.0.0.1"}, {18867936340463368, :"lookup_node2@127.0.0.1"}, {50681910485743633, :"lookup_node4@127.0.0.1"}, {55319291695019062, :"lookup_node4@127.0.0.1"}, {57636988639494176, :"lookup_node3@127.0.0.1"}, {77000307452109137, :"lookup_node1@127.0.0.1"}, {77200463374310568, :"lookup_node3@127.0.0.1"}, {84911773087455637, :"lookup_node4@127.0.0.1"}, {86970190936244068, :"lookup_node4@127.0.0.1"}, {90600812887495620, :"lookup_node4@127.0.0.1"}, {121757696338042739, :"lookup_node1@127.0.0.1"}, {136842215777953195, :"lookup_node2@127.0.0.1"}, {138713638965665363, :"lookup_node3@127.0.0.1"}, {155344314273407587, :"lookup_node4@127.0.0.1"}, {165504287695807568, :"lookup_node2@127.0.0.1"}, {174141511973200859, :"lookup_node1@127.0.0.1"}, {176842425576805405, :"lookup_node2@127.0.0.1"}, {176887251314100118, :"lookup_node2@127.0.0.1"}, {201442636334278995, :"lookup_node4@127.0.0.1"}, {210180374614964644, :"lookup_node3@127.0.0.1"}, {217476853691272799, :"lookup_node2@127.0.0.1"}, {220189871537580651, :"lookup_node2@127.0.0.1"}, {234527158141187087, :"lookup_node2@127.0.0.1"}, {239407038251305811, :"lookup_node1@127.0.0.1"}, {262143688230177771, :"lookup_node3@127.0.0.1"}, {276566900439087340, :"lookup_node1@127.0.0.1"}, {279205707087781401, :"lookup_node1@127.0.0.1"}, {292115027877842504, :"lookup_node2@127.0.0.1"}, {302124116700078892, :"lookup_node1@127.0.0.1"}, {330480583953434981, :"lookup_node1@127.0.0.1"}, {365297236823388237, :"lookup_node1@127.0.0.1"}, {374749903886077398, :"lookup_node4@127.0.0.1"}, {383807305750842785, :"lookup_node2@127.0.0.1"}, {387576567570158627, :"lookup_node2@127.0.0.1"}, {394401983481686230, :"lookup_node4@127.0.0.1"}, {394729716780795193, :"lookup_node3@127.0.0.1"}, {394973300925442604, :"lookup_node1@127.0.0.1"}, {403628672502635487, :"lookup_node1@127.0.0.1"}, {413153906159515808, :"lookup_node2@127.0.0.1"}, {428375044170371008, :"lookup_node2@127.0.0.1"}, {428913751594954740, :"lookup_node2@127.0.0.1"}, {434127240937844164, :"lookup_node1@127.0.0.1"}, {453198428459581518, :"lookup_node1@127.0.0.1"}, {458580434616858841, :"lookup_node2@127.0.0.1"}, {491534110203356192, :"lookup_node1@127.0.0.1"}, {492860860453293270, :"lookup_node1@127.0.0.1"}, {495039687366202942, :"lookup_node1@127.0.0.1"}, {506131336326355127, ...}, {...}, ...}, nodes: [:"lookup_node4@127.0.0.1", :"lookup_node3@127.0.0.1", :"lookup_node2@127.0.0.1", :"lookup_node1@127.0.0.1"], num_replicas: 512}, found node is lookup_node4@127.0.0.1

13:38:20.391 [debug] In cluster, get_node current node is :"lookup_node2@127.0.0.1" -- about to get node given CHOSEN key: key0, key state is #MapSet<["key00", "key01", "key02", "key03"]>, hash ring is %ExHashRing.HashRing{items: {{18867936340463368, :"lookup_node2@127.0.0.1"}, {57636988639494176, :"lookup_node3@127.0.0.1"}, {77000307452109137, :"lookup_node1@127.0.0.1"}, {77200463374310568, :"lookup_node3@127.0.0.1"}, {121757696338042739, :"lookup_node1@127.0.0.1"}, {136842215777953195, :"lookup_node2@127.0.0.1"}, {138713638965665363, :"lookup_node3@127.0.0.1"}, {165504287695807568, :"lookup_node2@127.0.0.1"}, {174141511973200859, :"lookup_node1@127.0.0.1"}, {176842425576805405, :"lookup_node2@127.0.0.1"}, {176887251314100118, :"lookup_node2@127.0.0.1"}, {210180374614964644, :"lookup_node3@127.0.0.1"}, {217476853691272799, :"lookup_node2@127.0.0.1"}, {220189871537580651, :"lookup_node2@127.0.0.1"}, {234527158141187087, :"lookup_node2@127.0.0.1"}, {239407038251305811, :"lookup_node1@127.0.0.1"}, {262143688230177771, :"lookup_node3@127.0.0.1"}, {276566900439087340, :"lookup_node1@127.0.0.1"}, {279205707087781401, :"lookup_node1@127.0.0.1"}, {292115027877842504, :"lookup_node2@127.0.0.1"}, {302124116700078892, :"lookup_node1@127.0.0.1"}, {330480583953434981, :"lookup_node1@127.0.0.1"}, {365297236823388237, :"lookup_node1@127.0.0.1"}, {383807305750842785, :"lookup_node2@127.0.0.1"}, {387576567570158627, :"lookup_node2@127.0.0.1"}, {394729716780795193, :"lookup_node3@127.0.0.1"}, {394973300925442604, :"lookup_node1@127.0.0.1"}, {403628672502635487, :"lookup_node1@127.0.0.1"}, {413153906159515808, :"lookup_node2@127.0.0.1"}, {428375044170371008, :"lookup_node2@127.0.0.1"}, {428913751594954740, :"lookup_node2@127.0.0.1"}, {434127240937844164, :"lookup_node1@127.0.0.1"}, {453198428459581518, :"lookup_node1@127.0.0.1"}, {458580434616858841, :"lookup_node2@127.0.0.1"}, {491534110203356192, :"lookup_node1@127.0.0.1"}, {492860860453293270, :"lookup_node1@127.0.0.1"}, {495039687366202942, :"lookup_node1@127.0.0.1"}, {506131336326355127, :"lookup_node1@127.0.0.1"}, {522569971258714570, :"lookup_node3@127.0.0.1"}, {531582283876380119, :"lookup_node3@127.0.0.1"}, {535312874067281998, :"lookup_node2@127.0.0.1"}, {543281662594400099, :"lookup_node2@127.0.0.1"}, {559682666310678795, :"lookup_node2@127.0.0.1"}, {567584585041226974, :"lookup_node1@127.0.0.1"}, {579335343161780941, :"lookup_node1@127.0.0.1"}, {634247486102941475, :"lookup_node1@127.0.0.1"}, {635823678737718177, :"lookup_node3@127.0.0.1"}, {644195515177537600, ...}, {...}, ...}, nodes: [:"lookup_node3@127.0.0.1", :"lookup_node1@127.0.0.1", :"lookup_node2@127.0.0.1"], num_replicas: 512}, found node is lookup_node1@127.0.0.1

13:38:20.409 [debug] snowflake server new_state is {1568399900397, 0, {:atomics, #Reference<0.1985860327.2097020931.239989>}, 0}, unique id is 6578345975834738688

13:38:20.754 [info]  [libcluster:chat] connected to :"lookup_node1@127.0.0.1"

13:38:20.754 [debug] From :"lookup_node1@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:20.754 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node1@127.0.0.1"

13:38:20.819 [debug] From :"lookup_node3@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:20.822 [info]  [libcluster:chat] connected to :"lookup_node3@127.0.0.1"

13:38:20.822 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node3@127.0.0.1"

13:38:21.624 [info]  [libcluster:chat] connected to :"lookup_node2@127.0.0.1"

13:38:21.624 [debug] From :"lookup_node4@127.0.0.1", Adding node :"lookup_node2@127.0.0.1"

13:38:21.624 [debug] From :"lookup_node2@127.0.0.1", Adding node :"lookup_node4@127.0.0.1"

13:38:23.410 [info]  3 Finished healing the simulated network partition

13:38:23.413 [debug] In cluster, get_node current node is :"lookup_node2@127.0.0.1" -- about to get node given CHOSEN key: key0, key state is #MapSet<["key00", "key01", "key02", "key03", "key04"]>, hash ring is %ExHashRing.HashRing{items: {{17825517198445669, :"lookup_node4@127.0.0.1"}, {18867936340463368, :"lookup_node2@127.0.0.1"}, {50681910485743633, :"lookup_node4@127.0.0.1"}, {55319291695019062, :"lookup_node4@127.0.0.1"}, {57636988639494176, :"lookup_node3@127.0.0.1"}, {77000307452109137, :"lookup_node1@127.0.0.1"}, {77200463374310568, :"lookup_node3@127.0.0.1"}, {84911773087455637, :"lookup_node4@127.0.0.1"}, {86970190936244068, :"lookup_node4@127.0.0.1"}, {90600812887495620, :"lookup_node4@127.0.0.1"}, {121757696338042739, :"lookup_node1@127.0.0.1"}, {136842215777953195, :"lookup_node2@127.0.0.1"}, {138713638965665363, :"lookup_node3@127.0.0.1"}, {155344314273407587, :"lookup_node4@127.0.0.1"}, {165504287695807568, :"lookup_node2@127.0.0.1"}, {174141511973200859, :"lookup_node1@127.0.0.1"}, {176842425576805405, :"lookup_node2@127.0.0.1"}, {176887251314100118, :"lookup_node2@127.0.0.1"}, {201442636334278995, :"lookup_node4@127.0.0.1"}, {210180374614964644, :"lookup_node3@127.0.0.1"}, {217476853691272799, :"lookup_node2@127.0.0.1"}, {220189871537580651, :"lookup_node2@127.0.0.1"}, {234527158141187087, :"lookup_node2@127.0.0.1"}, {239407038251305811, :"lookup_node1@127.0.0.1"}, {262143688230177771, :"lookup_node3@127.0.0.1"}, {276566900439087340, :"lookup_node1@127.0.0.1"}, {279205707087781401, :"lookup_node1@127.0.0.1"}, {292115027877842504, :"lookup_node2@127.0.0.1"}, {302124116700078892, :"lookup_node1@127.0.0.1"}, {330480583953434981, :"lookup_node1@127.0.0.1"}, {365297236823388237, :"lookup_node1@127.0.0.1"}, {374749903886077398, :"lookup_node4@127.0.0.1"}, {383807305750842785, :"lookup_node2@127.0.0.1"}, {387576567570158627, :"lookup_node2@127.0.0.1"}, {394401983481686230, :"lookup_node4@127.0.0.1"}, {394729716780795193, :"lookup_node3@127.0.0.1"}, {394973300925442604, :"lookup_node1@127.0.0.1"}, {403628672502635487, :"lookup_node1@127.0.0.1"}, {413153906159515808, :"lookup_node2@127.0.0.1"}, {428375044170371008, :"lookup_node2@127.0.0.1"}, {428913751594954740, :"lookup_node2@127.0.0.1"}, {434127240937844164, :"lookup_node1@127.0.0.1"}, {453198428459581518, :"lookup_node1@127.0.0.1"}, {458580434616858841, :"lookup_node2@127.0.0.1"}, {491534110203356192, :"lookup_node1@127.0.0.1"}, {492860860453293270, :"lookup_node1@127.0.0.1"}, {495039687366202942, :"lookup_node1@127.0.0.1"}, {506131336326355127, ...}, {...}, ...}, nodes: [:"lookup_node4@127.0.0.1", :"lookup_node3@127.0.0.1", :"lookup_node1@127.0.0.1", :"lookup_node2@127.0.0.1"], num_replicas: 512}, found node is lookup_node4@127.0.0.1

13:38:23.443 [debug] snowflake server new_state is {1568399903426, 3, {:atomics, #Reference<0.3132197130.2633891841.169203>}, 0}, unique id is 6578345988539297792

13:38:23.460 [debug] In cluster, get_node current node is :"lookup_node1@127.0.0.1" -- about to get node given CHOSEN key: key0, key state is #MapSet<["key00", "key01", "key02", "key03", "key04"]>, hash ring is %ExHashRing.HashRing{items: {{17825517198445669, :"lookup_node4@127.0.0.1"}, {18867936340463368, :"lookup_node2@127.0.0.1"}, {50681910485743633, :"lookup_node4@127.0.0.1"}, {55319291695019062, :"lookup_node4@127.0.0.1"}, {57636988639494176, :"lookup_node3@127.0.0.1"}, {77000307452109137, :"lookup_node1@127.0.0.1"}, {77200463374310568, :"lookup_node3@127.0.0.1"}, {84911773087455637, :"lookup_node4@127.0.0.1"}, {86970190936244068, :"lookup_node4@127.0.0.1"}, {90600812887495620, :"lookup_node4@127.0.0.1"}, {121757696338042739, :"lookup_node1@127.0.0.1"}, {136842215777953195, :"lookup_node2@127.0.0.1"}, {138713638965665363, :"lookup_node3@127.0.0.1"}, {155344314273407587, :"lookup_node4@127.0.0.1"}, {165504287695807568, :"lookup_node2@127.0.0.1"}, {174141511973200859, :"lookup_node1@127.0.0.1"}, {176842425576805405, :"lookup_node2@127.0.0.1"}, {176887251314100118, :"lookup_node2@127.0.0.1"}, {201442636334278995, :"lookup_node4@127.0.0.1"}, {210180374614964644, :"lookup_node3@127.0.0.1"}, {217476853691272799, :"lookup_node2@127.0.0.1"}, {220189871537580651, :"lookup_node2@127.0.0.1"}, {234527158141187087, :"lookup_node2@127.0.0.1"}, {239407038251305811, :"lookup_node1@127.0.0.1"}, {262143688230177771, :"lookup_node3@127.0.0.1"}, {276566900439087340, :"lookup_node1@127.0.0.1"}, {279205707087781401, :"lookup_node1@127.0.0.1"}, {292115027877842504, :"lookup_node2@127.0.0.1"}, {302124116700078892, :"lookup_node1@127.0.0.1"}, {330480583953434981, :"lookup_node1@127.0.0.1"}, {365297236823388237, :"lookup_node1@127.0.0.1"}, {374749903886077398, :"lookup_node4@127.0.0.1"}, {383807305750842785, :"lookup_node2@127.0.0.1"}, {387576567570158627, :"lookup_node2@127.0.0.1"}, {394401983481686230, :"lookup_node4@127.0.0.1"}, {394729716780795193, :"lookup_node3@127.0.0.1"}, {394973300925442604, :"lookup_node1@127.0.0.1"}, {403628672502635487, :"lookup_node1@127.0.0.1"}, {413153906159515808, :"lookup_node2@127.0.0.1"}, {428375044170371008, :"lookup_node2@127.0.0.1"}, {428913751594954740, :"lookup_node2@127.0.0.1"}, {434127240937844164, :"lookup_node1@127.0.0.1"}, {453198428459581518, :"lookup_node1@127.0.0.1"}, {458580434616858841, :"lookup_node2@127.0.0.1"}, {491534110203356192, :"lookup_node1@127.0.0.1"}, {492860860453293270, :"lookup_node1@127.0.0.1"}, {495039687366202942, :"lookup_node1@127.0.0.1"}, {506131336326355127, ...}, {...}, ...}, nodes: [:"lookup_node4@127.0.0.1", :"lookup_node3@127.0.0.1", :"lookup_node2@127.0.0.1", :"lookup_node1@127.0.0.1"], num_replicas: 512}, found node is lookup_node4@127.0.0.1

13:38:23.461 [debug] snowflake server new_state is {1568399903460, 3, {:atomics, #Reference<0.3132197130.2633891841.169203>}, 0}, unique id is 6578345988681904128

13:38:23.489 [debug] In cluster, get_node current node is :"lookup_node3@127.0.0.1" -- about to get node given CHOSEN key: key0, key state is #MapSet<["key00", "key01", "key02", "key03", "key04"]>, hash ring is %ExHashRing.HashRing{items: {{17825517198445669, :"lookup_node4@127.0.0.1"}, {18867936340463368, :"lookup_node2@127.0.0.1"}, {50681910485743633, :"lookup_node4@127.0.0.1"}, {55319291695019062, :"lookup_node4@127.0.0.1"}, {57636988639494176, :"lookup_node3@127.0.0.1"}, {77000307452109137, :"lookup_node1@127.0.0.1"}, {77200463374310568, :"lookup_node3@127.0.0.1"}, {84911773087455637, :"lookup_node4@127.0.0.1"}, {86970190936244068, :"lookup_node4@127.0.0.1"}, {90600812887495620, :"lookup_node4@127.0.0.1"}, {121757696338042739, :"lookup_node1@127.0.0.1"}, {136842215777953195, :"lookup_node2@127.0.0.1"}, {138713638965665363, :"lookup_node3@127.0.0.1"}, {155344314273407587, :"lookup_node4@127.0.0.1"}, {165504287695807568, :"lookup_node2@127.0.0.1"}, {174141511973200859, :"lookup_node1@127.0.0.1"}, {176842425576805405, :"lookup_node2@127.0.0.1"}, {176887251314100118, :"lookup_node2@127.0.0.1"}, {201442636334278995, :"lookup_node4@127.0.0.1"}, {210180374614964644, :"lookup_node3@127.0.0.1"}, {217476853691272799, :"lookup_node2@127.0.0.1"}, {220189871537580651, :"lookup_node2@127.0.0.1"}, {234527158141187087, :"lookup_node2@127.0.0.1"}, {239407038251305811, :"lookup_node1@127.0.0.1"}, {262143688230177771, :"lookup_node3@127.0.0.1"}, {276566900439087340, :"lookup_node1@127.0.0.1"}, {279205707087781401, :"lookup_node1@127.0.0.1"}, {292115027877842504, :"lookup_node2@127.0.0.1"}, {302124116700078892, :"lookup_node1@127.0.0.1"}, {330480583953434981, :"lookup_node1@127.0.0.1"}, {365297236823388237, :"lookup_node1@127.0.0.1"}, {374749903886077398, :"lookup_node4@127.0.0.1"}, {383807305750842785, :"lookup_node2@127.0.0.1"}, {387576567570158627, :"lookup_node2@127.0.0.1"}, {394401983481686230, :"lookup_node4@127.0.0.1"}, {394729716780795193, :"lookup_node3@127.0.0.1"}, {394973300925442604, :"lookup_node1@127.0.0.1"}, {403628672502635487, :"lookup_node1@127.0.0.1"}, {413153906159515808, :"lookup_node2@127.0.0.1"}, {428375044170371008, :"lookup_node2@127.0.0.1"}, {428913751594954740, :"lookup_node2@127.0.0.1"}, {434127240937844164, :"lookup_node1@127.0.0.1"}, {453198428459581518, :"lookup_node1@127.0.0.1"}, {458580434616858841, :"lookup_node2@127.0.0.1"}, {491534110203356192, :"lookup_node1@127.0.0.1"}, {492860860453293270, :"lookup_node1@127.0.0.1"}, {495039687366202942, :"lookup_node1@127.0.0.1"}, {506131336326355127, ...}, {...}, ...}, nodes: [:"lookup_node4@127.0.0.1", :"lookup_node2@127.0.0.1", :"lookup_node1@127.0.0.1", :"lookup_node3@127.0.0.1"], num_replicas: 512}, found node is lookup_node4@127.0.0.1

13:38:23.489 [debug] snowflake server new_state is {1568399903489, 3, {:atomics, #Reference<0.3132197130.2633891841.169203>}, 0}, unique id is 6578345988803538944

13:38:23.494 [info]  [6578345975834738688, 6578345988539297792, 6578345988681904128, 6578345988803538944]
.

Finished in 10.9 seconds
3 tests, 0 failures, 2 excluded

Randomized with seed 540641

13:38:23.494 [debug] From :"manager@127.0.0.1", removing node :"lookup_node2@127.0.0.1"

13:38:23.498 [debug] From :"manager@127.0.0.1", removing node :"lookup_node1@127.0.0.1"

13:38:23.496 [debug] From :"lookup_node3@127.0.0.1", removing node :"lookup_node1@127.0.0.1"

13:38:23.499 [debug] From :"manager@127.0.0.1", removing node :"lookup_node4@127.0.0.1"

13:38:23.500 [debug] From :"manager@127.0.0.1", removing node :"lookup_node3@127.0.0.1"


```

Multiple nodes generating new ids

![Logo](https://raw.githubusercontent.com/brpandey/snowflake/master/priv/images/generating_ids.png)

Happy coding, thanks! 

Bibek
