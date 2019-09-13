defmodule Mix.Tasks.Seed do
  @moduledoc """
  Custom mix task to seed node ids into dets files for proper system operation
  to simulate multiple nodes on a single host

  """
  def run(_) do
    Snowflake.Database.setup_all()
  end
end
