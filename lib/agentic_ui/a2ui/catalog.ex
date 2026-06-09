defmodule AgenticUi.A2UI.Catalog do
  @moduledoc """
  Loads the vendored MeldUI A2UI component catalog into memory at boot.

  The canonical source is `priv/a2ui/catalog.json` — bumped manually when a
  new MeldUI catalog ships, never fetched over the network at runtime. Cached
  via `Agent` because the validator reads it on every tool call.

  Two public catalog views:

    * `get/0` — the full catalog map (with descriptions, defaults, etc.).
      Used by `AgenticUi.A2UI.Validator` for the catalog semantic pass.
    * `slim_json/1` / `strip_descriptions/1` — pure helpers that drop every
      `description` field anywhere in the structure. Used by the LLM agent
      to build a leaner system prompt: descriptions are ~25% of the catalog
      JSON's mass and the model doesn't need them to render correctly.
  """
  use Agent
  require Logger

  @vendored_path Path.join(:code.priv_dir(:agentic_ui), "a2ui/catalog.json")

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(&load_vendored!/0, name: __MODULE__)
  end

  @doc "Returns the cached catalog map."
  @spec get() :: map()
  def get, do: Agent.get(__MODULE__, & &1)

  @doc "Force a reload from disk. Useful in IEx after bumping `priv/a2ui/catalog.json`."
  @spec refresh() :: :ok
  def refresh, do: Agent.update(__MODULE__, fn _ -> load_vendored!() end)

  @doc """
  Recursively strip every `"description"` key from a catalog map. Pure;
  callable at compile time (the LLM agent calls this on the catalog before
  embedding it in the system prompt).
  """
  @spec strip_descriptions(term()) :: term()
  def strip_descriptions(map) when is_map(map) do
    map
    |> Map.delete("description")
    |> Map.new(fn {k, v} -> {k, strip_descriptions(v)} end)
  end

  def strip_descriptions(list) when is_list(list), do: Enum.map(list, &strip_descriptions/1)
  def strip_descriptions(other), do: other

  @doc """
  Decode the given catalog JSON, strip descriptions, re-encode. Convenience
  for the agent's compile-time pipeline.
  """
  @spec slim_json(String.t()) :: String.t()
  def slim_json(catalog_json) when is_binary(catalog_json) do
    catalog_json
    |> Jason.decode!()
    |> strip_descriptions()
    |> Jason.encode!()
  end

  @doc """
  Per-component map of "prop names that carry child component IDs".

  Derived by walking each component's `allOf` leaf-object `properties` and
  picking the props whose schema points at A2UI's `ComponentId` definition
  (either directly, or as an array `items` ref).

  Used by `AgenticUi.A2UI.Validator` to distinguish a real child reference
  (e.g. `Card.child`, `Column.children`) from a literal-string prop that
  happens to share a name with one (e.g. `Markdown.content`, where `content`
  is a `DynamicString`, not a `ComponentId`).
  """
  @spec child_field_index() :: %{String.t() => MapSet.t(String.t())}
  def child_field_index, do: child_field_index(get())

  @spec child_field_index(map()) :: %{String.t() => MapSet.t(String.t())}
  def child_field_index(catalog) when is_map(catalog) do
    catalog
    |> Map.get("components", %{})
    |> Map.new(fn {name, defn} -> {name, leaf_child_fields(defn)} end)
  end

  defp leaf_child_fields(%{"allOf" => items}) when is_list(items) do
    items
    |> Enum.find(fn item -> is_map(item) and not Map.has_key?(item, "$ref") end)
    |> case do
      nil -> MapSet.new()
      leaf -> leaf |> Map.get("properties", %{}) |> child_props()
    end
  end

  defp leaf_child_fields(_), do: MapSet.new()

  defp child_props(props) do
    props
    |> Enum.flat_map(fn {name, schema} ->
      if component_id_field?(schema), do: [name], else: []
    end)
    |> MapSet.new()
  end

  defp component_id_field?(%{"$ref" => ref}) when is_binary(ref),
    do: String.contains?(ref, "ComponentId")

  defp component_id_field?(%{"type" => "array", "items" => items}),
    do: component_id_field?(items)

  defp component_id_field?(_), do: false

  defp load_vendored! do
    catalog = @vendored_path |> File.read!() |> Jason.decode!()

    Logger.info("[A2UI catalog] loaded vendored snapshot (#{map_size(catalog)} top-level keys)")

    catalog
  end
end
