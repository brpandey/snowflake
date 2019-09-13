defmodule Snowflake.Dispatch do
  @moduledoc """
  Dispatch handles the request dispatch either local dispatch
  or a load distribution remote snowflake dispatch commonly used

  A specific node or key can be specified or a random node

  We seed the random number generation upon process start up
  """

  use GenServer
  require Logger

  @random_key "random"

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Snowflake.Dispatch)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @impl GenServer
  def init(_) do
    Logger.debug("Starting dispatch server")
    {:ok, :ok, {:continue, :seedrand}}
  end

  @impl GenServer
  def handle_continue(:seedrand, :ok) do
    rand_helper()
    {:noreply, :ok}
  end

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    {:reply, select(key), state}
  end

  # No key specified use local node
  def select(no_key) when no_key in [:error, nil] do
    node = node()
    {do_select(node), node}
  end

  # Use a specific node
  def select(node) when is_atom(node) do
    {do_select(node), node}
  end

  # Pick a random node
  def select(@random_key) do
    node = Snowflake.Cluster.get_node()
    {do_select(node), node}
  end

  # Use provided key as input to consistent hash ring
  def select(key) when is_binary(key) do
    node = Snowflake.Cluster.get_node(key)
    {do_select(node), node}
  end

  def do_select(node) when is_atom(node) do
    # Use Task Supervisor over rpc call
    task = Task.Supervisor.async({Snowflake.TaskSupervisor, node}, Snowflake.Server, :get_id, [])
    Task.await(task)

    # The catch block is used to handle any software defects or network issues
  catch
    :exit, msg ->
      msg
  end

  def rand_helper() do
    # Seed psuedo random number generation
    # a word is 4 bytes or 32 bits, 3 words are 12 bytes
    <<a::32, b::32, c::32>> = :crypto.strong_rand_bytes(12)
    r_seed = {a, b, c}

    _ = :rand.seed(:exsplus, r_seed)
    _ = :rand.seed(:exsplus, r_seed)
  end
end
