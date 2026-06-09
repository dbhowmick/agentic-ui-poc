defmodule AgenticUi.LLM.Tools.UpdateComponents do
  @moduledoc """
  A2UI `updateComponents` envelope emitter. The `components` list is a flat
  adjacency list — each entry has `id`, `component` (the catalog name), and
  catalog-defined props. Reference children by ID, not inline. One of the
  components (in this batch or a previous one on the same surface) MUST have
  `id: "root"` so the surface has a renderable root.
  """
  use Jido.Action,
    name: "update_components",
    description:
      "Append or replace components in an existing A2UI surface. The `components` list is a flat adjacency list referencing children by ID. One component on the surface must have id=\"root\".",
    schema:
      Zoi.object(%{
        surface_id: Zoi.string(description: "Target surface ID (must already exist)."),
        components:
          Zoi.array(Zoi.map(Zoi.string(), Zoi.any()),
            description:
              "Flat list of component definitions. Each item has `id`, `component`, and catalog-specific props."
          )
      })

  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(args, ctx), do: AgenticUi.LLM.Tools.Emit.emit(:update_components, args, ctx)
end
