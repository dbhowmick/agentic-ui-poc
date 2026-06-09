defmodule AgenticUi.LLM.Tools.CreateSurface do
  @moduledoc """
  A2UI `createSurface` envelope emitter. Phase 2 stub: logs the call and acks.

  Phase 3 will validate the envelope and broadcast it to the conversation's
  channel topic via `Phoenix.PubSub`.
  """
  use Jido.Action,
    name: "create_surface",
    description:
      "Create a new A2UI surface bound to a root component. Must be called before any update_components on that surface_id.",
    schema:
      Zoi.object(%{
        surface_id: Zoi.string(description: "Stable identifier for the surface (e.g. 'main')."),
        root: Zoi.string(description: "Component ID of the surface's root component.")
      })

  require Logger

  @spec run(map(), map()) :: {:ok, map()}
  def run(args, ctx) do
    Logger.info("[A2UI tool] create_surface args=#{inspect(args)} ctx=#{inspect(ctx)}")
    {:ok, %{acknowledged: true}}
  end
end
