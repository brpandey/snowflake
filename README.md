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

Multiple nodes generating new ids

![Logo](https://raw.githubusercontent.com/brpandey/snowflake/master/priv/images/generating_ids.png)

Happy coding, thanks! 

Bibek
