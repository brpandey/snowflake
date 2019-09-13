defmodule Snowflake.WebTest do
  use ExUnit.Case, async: false
  use Plug.Test
  require Logger
  alias Snowflake.Test.Helper

  setup_all do
    IO.puts("Web Test")

    Helper.setup_nodes()

    # We also need to start HTTPoison
    HTTPoison.start()

    {:ok, %{}}
  end

  test "local unique id generation" do
    {:ok, response = %HTTPoison.Response{}} = HTTPoison.get("http://127.0.0.1:5454/lunique")

    parse_int(response.body)
  end

  test "unique id generation using remote random node" do
    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=random")

    parse_int(response.body)
  end

  test "unique id generation using key" do
    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=key00")

    IO.puts("key00")
    parse_int(response.body)

    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=key01")

    IO.puts("key01")
    parse_int(response.body)

    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=key02")

    IO.puts("key02")
    parse_int(response.body)

    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=key03")

    IO.puts("key03")
    parse_int(response.body)

    {:ok, response = %HTTPoison.Response{}} =
      HTTPoison.get("http://127.0.0.1:5454/dunique?target=key04")

    IO.puts("key04")
    parse_int(response.body)
  end

  def parse_int(str) do
    {id, _} = Integer.parse(str)
    IO.puts(id)
    true = Kernel.is_integer(id)
    Snowflake.Id.decode_u64_id(id) |> IO.inspect(label: "decoded value")
  end
end
