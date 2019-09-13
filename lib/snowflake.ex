defmodule Snowflake.Application do
  use Application

  def start(_, _) do
    Snowflake.System.start_link()
  end
end
