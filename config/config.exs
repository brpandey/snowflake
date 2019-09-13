# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :snowflake, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:snowflake, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env()}.exs"

# Prefix must match the names of the node list below it

config :snowflake,
  prefix: "lookup_node",
  port: 5454,
  db_folder: "persist",
  nodes: Enum.map(1..4 |> Enum.into([]), fn i -> "lookup_node#{i}@127.0.0.1" |> String.to_atom() end)


config :logger,
  # level: :warn   # For speed wrk tests
   level: :debug  # In order to see how the program is working ;)

import_config "#{Mix.env()}.exs"
