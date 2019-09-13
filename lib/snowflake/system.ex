defmodule Snowflake.System do
  @moduledoc """
  System gives the application structure through the system wide supervision tree in start_link/0

  If the entire system goes down when it comes back up the ids generated will continue to be unique
  as the basis is around the timestamp, per node unique node id, and counters to guard against submillisecond
  collisions so to speak
  """

  def start_link do
    # We use libcluster so we don't have to connect the nodes explicitly
    topologies = [
      chat: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]

    Supervisor.start_link(
      [
        {Cluster.Supervisor, [topologies, [name: Snowflake.NodeClusterSupervisor]]},
        Snowflake.Cluster,
        Snowflake.Database,
        Snowflake.Web,
        {Task.Supervisor, name: Snowflake.TaskSupervisor},
        Snowflake.Server
      ],
      strategy: :one_for_one
    )
  end
end
