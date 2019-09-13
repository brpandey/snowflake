defmodule Snowflake.Cluster do
  @moduledoc """
  The Cluster module was included to illustrate how a system could be resilient during node failures
  - e.g. a network partition

  If a request coming into node1 was to be routed to node3 but node3 is down it will get routed to another node
  The use case here is when you are using load distribution via a user supplied url target key param

  TODO: Add more unique keys per node using something like HashIds so we have better coverage when we do random()
  """

  use GenServer
  require Logger
  alias ExHashRing.HashRing

  @resync_delay 2_000
  @prefix Application.fetch_env!(:snowflake, :prefix)
  @test_nodes ["nonode@nohost", "manager@127.0.0.1"]
  @skip_list Enum.map(@test_nodes, &String.to_atom(&1))

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Snowflake.Cluster)
  end

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      name: Snowflake.Cluster
    }
  end

  def get_node(key \\ :random) do
    GenServer.call(__MODULE__, {:get_node, key})
  end

  def set_canonical_nodes(nodes) do
    GenServer.cast(__MODULE__, {:set_nodes, nodes})
  end

  @impl GenServer
  def init(_) do
    :net_kernel.monitor_nodes(true)

    init_state = %{keys: MapSet.new(["key00"]), ring: HashRing.new()}
    state = add_node(node(), init_state)

    Process.send_after(self(), :resync, @resync_delay)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get_node, :random}, _, state) do
    key = Enum.random(state.keys)

    node = HashRing.find_node(state.ring, key)

    Logger.debug(
      "In cluster, get_node current node is #{inspect(node())} -- about to get node given RANDOM key: #{
        key
      }, key state is #{inspect(state.keys)}, hash ring is #{inspect(state.ring)}, found node is #{
        node
      }"
    )

    {:reply, node, state}
  end

  @impl GenServer
  def handle_call({:get_node, key}, _, state) do
    node = HashRing.find_node(state.ring, key)

    Logger.debug(
      "In cluster, get_node current node is #{inspect(node())} -- about to get node given CHOSEN key: #{
        key
      }, key state is #{inspect(state.keys)}, hash ring is #{inspect(state.ring)}, found node is #{
        node
      }"
    )

    {:reply, node, state}
  end

  @impl GenServer
  def handle_cast({:set_nodes, nodes}, state) do
    Logger.debug("Setting canonical node list nodes #{inspect(nodes)}")
    state = Enum.reduce(nodes, state, fn node, acc -> add_node(node, acc) end)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:resync, state) do
    Logger.debug(
      "Re-syncing node list after 10 seconds to make sure we have all the connected nodes"
    )

    state = Enum.reduce(Node.list(), state, fn node, acc -> add_node(node, acc) end)

    Logger.debug("Resynced state of keys is #{inspect(state.keys)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:nodeup, node}, state) do
    {:noreply, add_node(node, state)}
  end

  @impl GenServer
  def handle_info({:nodedown, node}, state) do
    {:noreply, remove_node(node, state)}
  end

  # Skip node -- arises during mix test
  def add_node(skip, state) when skip in @skip_list, do: state

  def add_node(node_name, _state = %{keys: keys, ring: hr}) when is_atom(node_name) do
    Logger.debug("From #{inspect(node())}, Adding node #{inspect(node_name)}")

    key_list = node_keys(node_name)
    keys = Enum.reduce(key_list, keys, fn k, acc -> MapSet.put(acc, k) end)

    hr =
      case HashRing.add_node(hr, node_name) do
        :error -> hr
        {:ok, hr} -> hr
      end

    %{keys: keys, ring: hr}
  end

  def remove_node(node_name, _state = %{keys: keys, ring: hr}) do
    Logger.debug("From #{inspect(node())}, removing node #{inspect(node_name)}")

    key_list = node_keys(node_name)
    keys = Enum.reduce(key_list, keys, fn k, acc -> MapSet.delete(acc, k) end)

    hr =
      case HashRing.remove_node(hr, node_name) do
        :error -> hr
        {:ok, hr} -> hr
      end

    %{keys: keys, ring: hr}
  end

  def node_keys(node_name) when is_atom(node_name) do
    [prefix, _] = node_name |> Atom.to_string() |> String.split("@", parts: 2)

    k1 =
      case String.contains?(prefix, @prefix) do
        true -> String.replace(prefix, @prefix, "key0")
        _ -> prefix
      end

    #    Improve coverage of finding node
    #    k2 = Hashids.encode(@hash_id, String.to_charlist(k1))
    #    k3 = Hashids.encode(@hash_id, String.to_charlist(k1) |> Enum.shuffle())

    [k1]
  end
end
