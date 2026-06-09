defmodule AgenticUi.LLM.Tools.DeleteSurface do
  @moduledoc """
  A2UI `deleteSurface` envelope emitter. Tears down a surface and frees its
  data model. Call only when the user explicitly asks to remove a rendered
  UI, or when transitioning between unrelated surfaces.
  """
  use Jido.Action,
    name: "delete_surface",
    description: "Tear down an A2UI surface and free its data model.",
    schema: Zoi.object(%{surface_id: Zoi.string(description: "Surface ID to remove.")})

  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(args, ctx), do: AgenticUi.LLM.Tools.Emit.emit(:delete_surface, args, ctx)
end
