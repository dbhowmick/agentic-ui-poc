defmodule AgenticUi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AgenticUiWeb.Telemetry,
      AgenticUi.Repo,
      {DNSCluster, query: Application.get_env(:agentic_ui, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgenticUi.PubSub},
      {Oban, Application.fetch_env!(:agentic_ui, Oban)},
      AgenticUi.Jido,
      # Start a worker by calling: AgenticUi.Worker.start_link(arg)
      # {AgenticUi.Worker, arg},
      # Start to serve requests, typically the last entry
      AgenticUiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgenticUi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgenticUiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
