defmodule Snowflake.Server do
  @moduledoc """
  Server represents the single process per node that handles id generation
  with assist from the auxiliary database process

  It relies on the Snowflake.Id module for the unique id generation and assists
  this process by being stateful.

  The new OTP 21.2 :counters module is used to provide fast counter generation

  If a node is restarted or this process restarted it just picks up with the same logic
  Since time is monotonicly increasing no explicity coordination with other nodes or persistence
  is required other than a persistant node id
  """

  use GenServer
  require Logger

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: Snowflake.Server)
  end

  def get_id() do
    GenServer.call(__MODULE__, :get_id)
  end

  def init(_) do
    Logger.debug("Starting snowflake server")
    node_id = Snowflake.Database.get(:node_id) |> String.to_integer()
    counter_ref = :counters.new(1, [])
    counter = :counters.get(counter_ref, 1)
    state = {Snowflake.Id.timestamp(), node_id, counter_ref, counter}
    {:ok, state}
  end

  def handle_call(:get_id, _from, state) do
    try do
      {unique_id, new_state} = Snowflake.Id.timestamp() |> Snowflake.Id.get_id(state)

      Logger.debug(
        "snowflake server new_state is #{inspect(new_state)}, unique id is #{unique_id}"
      )

      {:reply, unique_id, new_state}
    rescue
      # Handle software defects if necessary
      e in RuntimeError ->
        %RuntimeError{message: msg} = e
        {:reply, {:error, msg}, state}
    end
  end
end
