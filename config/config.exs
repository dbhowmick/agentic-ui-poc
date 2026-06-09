# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :agentic_ui,
  namespace: AgenticUi,
  ecto_repos: [AgenticUi.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :agentic_ui, AgenticUiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgenticUiWeb.ErrorHTML, json: AgenticUiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgenticUi.PubSub,
  live_view: [signing_salt: "7yLF+0Ai"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :agentic_ui, AgenticUi.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Default model alias used by AgenticUi.LLM.Agent. Tune here, not in code.
config :jido_ai,
  model_aliases: %{
    default: "anthropic:claude-sonnet-4-5-20250929"
  }

# Auth configuration is inserted above the next line by `mix phoenix_vue.gen.auth`.
# phoenix_vue:gen.auth:config_anchor

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
