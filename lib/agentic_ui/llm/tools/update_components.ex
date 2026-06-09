defmodule AgenticUi.LLM.Tools.UpdateComponents do
  @moduledoc """
  A2UI `updateComponents` envelope emitter. Phase 2 stub: logs the call and acks.
  """
  use Jido.Action,
    name: "update_components",
    description:
      "Append or replace components in an existing A2UI surface. Components are a flat adjacency list referencing children by ID.",
    schema:
      Zoi.object(%{
        surface_id: Zoi.string(description: "Target surface ID (must already exist)."),
        components:
          Zoi.array(Zoi.map(Zoi.string(), Zoi.any()),
            description: "Flat list of component definitions following the MeldUI catalog schema."
          )
      })

  require Logger

  @spec run(map(), map()) :: {:ok, map()}
  def run(args, ctx) do
    Logger.info("[A2UI tool] update_components args=#{inspect(args)} ctx=#{inspect(ctx)}")
    {:ok, %{acknowledged: true}}
  end
end
