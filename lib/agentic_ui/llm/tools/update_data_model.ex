defmodule AgenticUi.LLM.Tools.UpdateDataModel do
  @moduledoc """
  A2UI `updateDataModel` envelope emitter. `path` is a JSON Pointer naming a
  location in the surface's data model (e.g. `/user/name`). Omit `path` (or
  set it to `/`) to replace the whole model. Omit `value` to delete the key
  at `path`.
  """
  use Jido.Action,
    name: "update_data_model",
    description:
      "Patch the data model of an A2UI surface. Use `path` (JSON Pointer) to address a node and `value` to set it. Omit `value` to delete.",
    schema:
      Zoi.object(%{
        surface_id: Zoi.string(description: "Target surface ID."),
        path:
          Zoi.optional(
            Zoi.string(
              description:
                "JSON Pointer to the data model node, e.g. \"/user/name\". Defaults to root."
            )
          ),
        # `Zoi.any/0` has no JSON Schema encoder (Jido/jido_ai turns the action
        # schema into JSON Schema to send to Anthropic), so the value field is
        # a union of all JSON-encodable primitives. Objects are accepted as
        # `Zoi.map(Zoi.string(), Zoi.any())` whose encoder falls through to a
        # permissive `{type: object}`. Arrays must be wrapped in an object
        # (set `path` to the array's parent).
        value:
          Zoi.optional(
            Zoi.union(
              [
                Zoi.string(),
                Zoi.integer(),
                Zoi.float(),
                Zoi.boolean(),
                Zoi.map(Zoi.string(), Zoi.any())
              ],
              description: "The new value. Omit to delete the key at `path`."
            )
          )
      })

  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(args, ctx), do: AgenticUi.LLM.Tools.Emit.emit(:update_data_model, args, ctx)
end
