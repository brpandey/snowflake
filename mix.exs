defmodule Snowflake.MixProject do
  use Mix.Project

  def project do
    [
      app: :snowflake,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Snowflake.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 0.11.0"},
      {:plug_cowboy, "~> 2.0"},
      {:libcluster, "~> 3.1"},
      {:ex_hash_ring, "~> 3.0"},
      {:local_cluster, "~> 1.0", only: [:dev, :test]},
      {:schism, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
