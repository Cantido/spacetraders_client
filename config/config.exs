# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :spacetraders_client, SpacetradersClient.Cache,
  # When using :shards as backend
  # backend: :shards,
  # GC interval for pushing new generation: 12 hrs
  gc_interval: :timer.hours(12),
  # Max 1 million entries in cache
  max_size: 1_000_000,
  # Max 2 GB of memory
  allocated_memory: 2_000_000_000,
  # GC min timeout: 10 sec
  gc_cleanup_min_timeout: :timer.seconds(10),
  # GC max timeout: 10 min
  gc_cleanup_max_timeout: :timer.minutes(10)

config :spacetraders_client,
  ecto_repos: [SpacetradersClient.Repo],
  generators: [timestamp_type: :utc_datetime]

config :spacetraders_client, SpacetradersClient.Repo,
  database: "tmp/#{config_env()}.db",
  migration_timestamps: [
    type: :utc_datetime
  ]

config :ex_cldr,
  default_locale: "en",
  default_backend: SpacetradersClient.Cldr

config :ex_money,
  exchange_rates_retrieve_every: :never,
  log_failure: nil

# Configures the endpoint
config :spacetraders_client, SpacetradersClientWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SpacetradersClientWeb.ErrorHTML, json: SpacetradersClientWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SpacetradersClient.PubSub,
  live_view: [signing_salt: "uTAYUwJB"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :spacetraders_client, SpacetradersClient.Mailer, adapter: Swoosh.Adapters.Local

config :tesla, Tesla.Middleware.Logger, filter_headers: ["authorization"]

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  spacetraders_client: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  spacetraders_client: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :phoenix_template, :format_encoders, svg: Phoenix.HTML.Engine

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
