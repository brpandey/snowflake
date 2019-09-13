defmodule Snowflake.Web do
  @moduledoc """
  Web layer to handle two types of queries
  `/lunique` generates ids locally
  `/dunique` generates id using peer node distribution
  """

  use Plug.Router
  require Logger

  @key_name "target"

  plug(:match)
  plug(:dispatch)

  def child_spec(_arg) do
    # Increasing connections didn't change availability much
    # options: [port: port(), protocol_options: [max_keepalive: 5_000_000]],

    Plug.Cowboy.child_spec(
      scheme: :http,
      options: [port: port()],
      # options: [port: port(), protocol_options: [max_keepalive: 5_000_000]],
      plug: __MODULE__
    )
  end

  # curl 'http://localhost:5454/lunique'
  # curl 'http://localhost:5454/dunique?target=random'
  # curl 'http://localhost:5454/dunique?target=key1'

  # Unique id generation with local snowflake
  get "/lunique" do
    process(conn, nil)
  end

  # Unique id generation with partitioned possibly remote id generation for load distribution
  get "/dunique" do
    conn = Plug.Conn.fetch_query_params(conn)

    case Map.fetch(conn.params, @key_name) do
      :error -> process(conn, :error)
      {:ok, key} -> process(conn, key)
    end
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end

  defp process(conn, key) do
    case Snowflake.Dispatch.select(key) do
      {value, _n} when is_integer(value) ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "#{value}")

      {{:timeout, _}, _n} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(503, "Service Unavailable - Timeout")

      {other, _n} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(500, "#{inspect(other)}")
    end
  end

  # Supports cmd line node starts as well as per node port settings in tests
  defp port do
    full_name = Node.self()

    [name, _] =
      full_name
      |> Atom.to_string()
      |> String.split("@")

    name = name |> String.upcase()

    name_specific_port = System.get_env("#{name}_PORT")
    specific_port = System.get_env("PORT")
    default_port = "5454"

    String.to_integer(name_specific_port || specific_port || default_port)
  end
end
