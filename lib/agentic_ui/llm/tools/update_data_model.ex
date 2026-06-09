defmodule AgenticUi.LLM.Tools.UpdateDataModel do
  @moduledoc """
  A2UI `updateDataModel` envelope emitter. Phase 2 stub: logs the call and acks.
  """
  use Jido.Action,
    name: "update_data_model",
    description:
      "Patch the data model of an A2UI surface. Component bindings re-resolve against the new values.",
    schema:
      Zoi.object(%{
        surface_id: Zoi.string(description: "Target surface ID."),
        data:
          Zoi.map(Zoi.string(), Zoi.any(),
            description: "New data model values to merge into the surface state."
          )
      })

  require Logger

  @spec run(map(), map()) :: {:ok, map()}
  def run(args, ctx) do
    Logger.info("[A2UI tool] update_data_model args=#{inspect(args)} ctx=#{inspect(ctx)}")
    {:ok, %{acknowledged: true}}
  end
end
