import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/agentic_ui start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :agentic_ui, AgenticUiWeb.Endpoint, server: true
end

config :agentic_ui, AgenticUiWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# ----------------------------------------------------------------------------
# Oban — two-release topology
#
# RELEASE_NAME is set by the release script (`bin/<release_name> start`).
# In dev / iex / test it's nil, so every queue runs in one node — handy for
# local development. In prod, split into two releases:
#
#   - `agentic_ui_server`     → web traffic + light jobs (default,
#                                          mailer). Hosts the cron plugin.
#   - `agentic_ui_processors` → heavy background work. Add queues
#                                          (e.g. embeddings, conversions) as
#                                          features land. Pruner only.
#
# Cron jobs live on the server release so they're declared in one place even
# though they may enqueue work that processors consume.
# ----------------------------------------------------------------------------
oban_queues =
  case System.get_env("RELEASE_NAME") do
    "agentic_ui_server" ->
      [default: 10, mailer: 5]

    "agentic_ui_processors" ->
      # Add heavy queues here as features land (e.g. documents: 4, embeddings: 2).
      [default: 10]

    _ ->
      [default: 10, mailer: 5]
  end

# Generator-managed cron entries. `mix phoenix_vue.gen.auth` replaces the next
# line with its sweeper schedule. Hand-edit the list below to add your own.
auth_crontab = []
project_crontab = []

oban_plugins =
  if System.get_env("RELEASE_NAME") == "agentic_ui_processors" do
    [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]
  else
    [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
      {Oban.Plugins.Cron, crontab: auth_crontab ++ project_crontab}
    ]
  end

config :agentic_ui, Oban,
  repo: AgenticUi.Repo,
  queues: oban_queues,
  plugins: oban_plugins

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :agentic_ui, AgenticUi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :agentic_ui, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :agentic_ui, AgenticUiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :agentic_ui, AgenticUiWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :agentic_ui, AgenticUiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :agentic_ui, AgenticUi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Auth prod overrides (cookie domain, secure flag, etc.) are inserted above
  # the next line by `mix phoenix_vue.gen.auth`.
  # phoenix_vue:gen.auth:prod_anchor
end
