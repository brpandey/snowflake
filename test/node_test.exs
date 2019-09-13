defmodule Snowflake.NodesTest do
  use ExUnit.Case, async: false
  require Logger
  alias Snowflake.Test.Helper

  setup_all do
    nodes = Helper.setup_nodes()
    {:ok, nodes: nodes}
  end

  test "request is routed to specific box", %{nodes: nodes} do
    [_n1, _n2, _n3, n4] = nodes
    {_id, ^n4} = Snowflake.Dispatch.select(n4)
  end

  test "request is routed to a specific box using consistent hashing", %{nodes: nodes} do
    [_n1, _n2, _n3, n4] = nodes

    {_id, ^n4} = Snowflake.Dispatch.select("key0")
  end

  test "remote snowflakes rerouted when node not accessible, and re-accessible when partition heals",
       %{nodes: nodes} do
    [n1, n2, n3, n4] = nodes

    key = "key0"

    Logger.info("1 About to partition")

    # Partition and wait for changes to propagate
    Schism.partition([n4])
    Process.sleep(2_000)

    Logger.info("2 Partitioned n4 from rest of cluster")

    # The key should ordinarily be directed to node 4 using consistent hashing
    # (if there weren't a network partition that is)

    # The manager node which this is running in can still access the partitioned node
    # ( so it can successfully un-partition or heal otherwise if it didn't have a link then it couldn't :) )

    assert ^n4 = Snowflake.Cluster.get_node(key)

    # Node 2 should not be able to generate unique ids on n4,
    # instead the consistent hash ring gets updated and the new node that generated the key is n1
    assert {v1, ^n1} = :rpc.call(n2, Snowflake.Dispatch, :select, [key])

    # Heal the partition(only current node can do since it is only one with still a link to n4)
    # Wait for changes to propagate
    Schism.heal([n4])
    Process.sleep(3_000)

    Logger.info("3 Finished healing the simulated network partition")

    # Node 2 should be able to generate unique ids on n4, now that its back up instead of n1.
    # The consistent hash ring has been updated after the Schism.heal event
    assert {v2, ^n4} = :rpc.call(n2, Snowflake.Dispatch, :select, [key])

    # Same as true for n1 and n3
    assert {v3, ^n4} = :rpc.call(n1, Snowflake.Dispatch, :select, [key])
    assert {v4, ^n4} = :rpc.call(n3, Snowflake.Dispatch, :select, [key])

    values = [v1, v2, v3, v4]

    Logger.info("#{inspect(values)}")
  end
end
