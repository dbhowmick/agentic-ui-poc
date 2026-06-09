defmodule AgenticUiWeb.UserSocket do
  @moduledoc "WebSocket entry point for the Vue SPA. No auth (Phase 0 non-goal)."
  use Phoenix.Socket

  channel "chat:*", AgenticUiWeb.ChatChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
