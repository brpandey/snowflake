defmodule Snowflake.Database do
  @moduledoc """
  This module was written to simulate a k/v database layer
  where a value per node could be seeded and retrieved

  The node ids are stored in a custom dets file

  The mostly arcane :dets was used as it was natively supported

  The node ids can be created by running the custom mix task `mix seed`
  which invokes setup_all/0
  """

  use GenServer
  require Logger

  @tbl :node_id_persist
  @valid_ids 0..1023
  @dets_file_name "unique1024.dets"
  @key "node_id"
  @test_mgr_node_port "1023"

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Snowflake.Database)
  end

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      name: Snowflake.Database
    }
  end

  def get(:node_id) do
    GenServer.call(__MODULE__, {:get, :node_id})
  end

  @impl GenServer
  def init(_) do
    {:ok, :ok, {:continue, :load}}
  end

  @impl GenServer

  def handle_continue(:load, :ok) do

    case load_local(@tbl, node()) do
      {:ok, @tbl} ->
        case read(@tbl) do
          [{@key, node_id}] ->
            {:noreply, node_id}
          [] ->
            raise "Unable to retrieve dets file contents, was it seeded correctly using mix seed?"
        end
      :test_node ->
        {:noreply, @test_mgr_node_port}

      # If we can't read from the dets file correctly raise
      {:error, reason} ->
        raise "Unable to open dets file #{inspect(reason)}"
    end
  end

  @impl GenServer
  def handle_call({:get, :node_id}, _, node_id) do
    {:reply, node_id, node_id}
  end

  @doc """
  Terminate callback
  Close the dets file
  """

  @impl GenServer
  def terminate(_reason, _state) do
    close(@tbl)
    _ = Logger.debug("Terminating Snowflake Database Server")
    :ok
  end

  # We similuate multiple nodes on a single host with per node directories under the
  # priv directory
  def setup_all() do
    node_list = Application.fetch_env!(:snowflake, :nodes)

    Logger.info("node list is #{inspect(node_list)}")

    size = Enum.count(node_list)

    # Generate the list of ids taking only the amount of nodes currently available
    ids_list = @valid_ids |> Enum.take(size)
    zipped = Enum.zip(node_list, ids_list)

    # For each pair, setup the path and load the tables properly
    # seeding with the proper value
    Enum.each(zipped, fn {node_name, node_id} ->
      node_name = Atom.to_string(node_name)
      {:ok, @tbl} = load_single(@tbl, node_name)
      seed(@tbl, node_id)
      close(@tbl)
    end)
  end

  def load_local(_table_name, :nonode@nohost), do: :test_node
  def load_local(table_name, node), do: load_single(table_name, "#{node}")

  defp load_single(table_name, node_name, seed \\ false)
       when is_atom(table_name) and is_binary(node_name) do
    # If these files don't exist write them
    dir = Application.fetch_env!(:snowflake, :db_folder)
    [name_prefix, _] = node_name |> String.split("@")

    db_folder = "/#{dir}/#{name_prefix}/"
    base_path = :code.priv_dir(:snowflake)
    db_path = base_path ++ String.to_charlist(db_folder)

    File.mkdir_p!(db_path)
    path = Path.absname(@dets_file_name, db_path)

    if seed do
      File.rm(path)
    end

    # Erlang prefers charlist
    path_charlist = String.to_charlist(path)

    :dets.open_file(table_name, file: path_charlist, type: :set)
  end

  defp seed(table_name, value) when is_atom(table_name) and is_integer(value) do
    :dets.insert_new(table_name, {@key, "#{value}"})

    case read(table_name) do
      [{@key, v}] when is_binary(v) ->
        v

      err ->
        raise "Unsupported read table value #{inspect(err)}"
    end
  end

  defp read(table_name) when is_atom(table_name) do
    # Below can only be used in the REPL, have to explicitly use parse transform-ish format
    # select_all = :ets.fun2ms(&(&1))
    select_all = [{:"$1", [], [:"$1"]}]
    :dets.select(table_name, select_all)
  end

  # Apparently dets likes to be explicitly closed or so I've heard :)
  defp close(table_name) do
    :dets.close(table_name)
  end
end
