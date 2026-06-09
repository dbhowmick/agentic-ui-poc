defmodule AgenticUi.LLM.Tools.DeleteSurface do
  @moduledoc """
  A2UI `deleteSurface` envelope emitter. Phase 2 stub: logs the call and acks.
  """
  use Jido.Action,
    name: "delete_surface",
    description: "Tear down an A2UI surface and free its data model.",
    schema: Zoi.object(%{surface_id: Zoi.string(description: "Surface ID to remove.")})

  require Logger

  @spec run(map(), map()) :: {:ok, map()}
  def run(args, ctx) do
    Logger.info("[A2UI tool] delete_surface args=#{inspect(args)} ctx=#{inspect(ctx)}")
    {:ok, %{acknowledged: true}}
  end
end
