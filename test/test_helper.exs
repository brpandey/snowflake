ExUnit.start()

defmodule Snowflake.Test.Helper do
  def setup_nodes do
    System.put_env("PORT", "5454")
    System.put_env("LOOKUP_NODE1_PORT", "5455")
    System.put_env("LOOKUP_NODE2_PORT", "5456")
    System.put_env("LOOKUP_NODE3_PORT", "5457")
    System.put_env("LOOKUP_NODE4_PORT", "5458")

    Application.ensure_all_started(:snowflake)

    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("lookup_node", 4)
    Snowflake.Cluster.set_canonical_nodes([Node.self() | nodes])

    # Wait for manager node to get caught up
    Process.sleep(2_000)

    nodes
  end
end
