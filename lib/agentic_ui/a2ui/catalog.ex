defmodule AgenticUi.A2UI.Catalog do
  @moduledoc """
  Loads the MeldUI A2UI component catalog into memory at boot.

  At `start_link/1` we try to fetch the published catalog from
  `https://meldui.dipayanb.com/a2ui/v1/catalog.json`. On any failure (timeout,
  non-200, network down) we log a warning and fall back to the vendored snapshot
  at `priv/a2ui/catalog.json`.

  Backed by an `Agent` — the catalog is set once at boot and read at most once
  per `Jido.AgentServer` start, so a single-process Agent is plenty.
  """
  use Agent
  require Logger

  @catalog_url "https://meldui.dipayanb.com/a2ui/v1/catalog.json"
  @fetch_timeout_ms 5_000

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(&load/0, name: __MODULE__)
  end

  @doc "Returns the cached catalog map."
  @spec get() :: map()
  def get, do: Agent.get(__MODULE__, & &1)

  @doc "Refetches the catalog from the upstream URL."
  @spec refresh() :: :ok
  def refresh, do: Agent.update(__MODULE__, fn _ -> load() end)

  defp load do
    case fetch_remote() do
      {:ok, catalog} ->
        Logger.info(
          "[A2UI catalog] loaded from #{@catalog_url} (#{map_size(catalog)} top-level keys)"
        )

        catalog

      {:error, reason} ->
        Logger.warning(
          "[A2UI catalog] remote fetch failed (#{inspect(reason)}); using vendored snapshot"
        )

        load_vendored!()
    end
  end

  defp fetch_remote do
    case Req.get(@catalog_url, receive_timeout: @fetch_timeout_ms, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp load_vendored! do
    path = Path.join(:code.priv_dir(:agentic_ui), "a2ui/catalog.json")
    path |> File.read!() |> Jason.decode!()
  end
end
