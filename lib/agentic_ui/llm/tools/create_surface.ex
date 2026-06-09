defmodule AgenticUi.LLM.Tools.CreateSurface do
  @moduledoc """
  A2UI `createSurface` envelope emitter.

  Per A2UI v0.9 the surface is created with a stable `surface_id`. The root
  component is named by giving it `id: "root"` in a subsequent
  `update_components` call — the envelope itself only carries the surface ID
  and a catalog ID. The catalog ID defaults to MeldUI's published catalog and
  rarely needs to be overridden.
  """
  use Jido.Action,
    name: "create_surface",
    description:
      "Create a new A2UI surface. Must be called before any update_components / update_data_model on the same surface_id. Choose a stable surface_id (use \"main\" for a single-surface response).",
    schema:
      Zoi.object(%{
        surface_id:
          Zoi.string(
            description:
              "Stable identifier for the surface. Use \"main\" if there is only one surface."
          ),
        catalog_id:
          Zoi.optional(
            Zoi.string(
              description:
                "Catalog ID for this surface. Defaults to the MeldUI catalog; only override if you know what you're doing."
            )
          )
      })

  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(args, ctx), do: AgenticUi.LLM.Tools.Emit.emit(:create_surface, args, ctx)
end
