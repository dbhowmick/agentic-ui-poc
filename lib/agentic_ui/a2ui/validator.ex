defmodule AgenticUi.A2UI.Validator do
  @moduledoc """
  Two-pass validation for A2UI v0.9 envelopes targeting the MeldUI catalog.

  1. JSON Schema validation against the vendored
     `priv/a2ui/schemas/v0_9/server_to_client.json` (envelope wire shape).
  2. For `updateComponents` envelopes only, a catalog semantic pass:
     - every component's `component` name exists in the loaded MeldUI catalog
     - the catalog's leaf `required` props are present on the component object
     - children referenced via known child-fields resolve either inside this
       envelope's component list or inside the caller-supplied
       `:known_component_ids` set (collected from prior persisted envelopes)

  On any failure returns `{:error, formatted_string}` shaped for direct
  consumption by the LLM as a recoverable tool result.

  Phase 3 deliberately keeps the catalog pass shallow — full deep prop
  validation against the catalog's `$ref` graph is Phase 6 hardening.
  """

  alias AgenticUi.A2UI.Catalog

  @schemas_dir Path.join(:code.priv_dir(:agentic_ui), "a2ui/schemas/v0_9")
  @schema_path Path.join(@schemas_dir, "server_to_client.json")
  @external_resource @schema_path

  @raw_schema_json File.read!(@schema_path)

  @child_fields ~w(child children content header footer items)

  @type stage :: :schema | :catalog
  @type validation_error :: %{stage: stage(), message: String.t()}
  @type opts :: [known_component_ids: MapSet.t()]

  @spec validate(map(), opts()) :: :ok | {:error, String.t()}
  def validate(envelope, opts \\ []) when is_map(envelope) do
    with :ok <- schema_validate(envelope) do
      catalog_validate(envelope, opts)
    end
  end

  # --- schema pass ---

  defp schema_validate(envelope) do
    case ExJsonSchema.Validator.validate(resolved_schema(), envelope) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error, "schema: " <> format_schema_errors(errors)}
    end
  end

  defp resolved_schema do
    case :persistent_term.get({__MODULE__, :resolved}, nil) do
      nil ->
        resolved =
          @raw_schema_json
          |> Jason.decode!()
          |> downgrade_to_draft_07()
          |> patch_external_refs()
          |> ExJsonSchema.Schema.resolve()

        :persistent_term.put({__MODULE__, :resolved}, resolved)
        resolved

      resolved ->
        resolved
    end
  end

  # `ex_json_schema` supports draft 4 / 6 / 7. The vendored schema declares
  # draft 2020-12 and uses `$defs`. Rewrite to draft-07 with `definitions`.
  # All features we use (`oneOf`, `$ref`, `const`, `required`, `additionalProperties`)
  # are draft-07 compatible.
  defp downgrade_to_draft_07(schema) do
    schema
    |> Map.put("$schema", "http://json-schema.org/draft-07/schema#")
    |> rename_defs_key()
    |> walk(fn
      %{"$ref" => "#/$defs/" <> rest} = m -> Map.put(m, "$ref", "#/definitions/" <> rest)
      other -> other
    end)
  end

  defp rename_defs_key(%{"$defs" => defs} = schema) do
    schema
    |> Map.delete("$defs")
    |> Map.put("definitions", defs)
  end

  defp rename_defs_key(schema), do: schema

  # The vendored schema uses `$ref` into a sibling `catalog.json` for the
  # `anyComponent` and `theme` shapes. We don't ship `catalog.json` at that
  # `$id` — the MeldUI catalog lives at a different URL and uses a different
  # internal structure. Substitute minimal local shapes so envelope validation
  # is self-contained; the catalog pass below covers component-level checks.
  defp patch_external_refs(schema) do
    walk(schema, fn
      %{"$ref" => "catalog.json#/$defs/anyComponent"} ->
        %{
          "type" => "object",
          "required" => ["id", "component"],
          "properties" => %{
            "id" => %{"type" => "string"},
            "component" => %{"type" => "string"}
          }
        }

      %{"$ref" => "catalog.json#/$defs/theme"} ->
        %{"type" => "object"}

      other ->
        other
    end)
  end

  defp walk(map, fun) when is_map(map) do
    map
    |> Map.new(fn {k, v} -> {k, walk(v, fun)} end)
    |> fun.()
  end

  defp walk(list, fun) when is_list(list), do: Enum.map(list, &walk(&1, fun))
  defp walk(other, _fun), do: other

  defp format_schema_errors(errors) when is_list(errors) do
    errors
    |> Enum.map_join("; ", fn
      %ExJsonSchema.Validator.Error{error: err, path: path} ->
        "#{path} — #{ExJsonSchema.Validator.Error.StringFormatter.format(err)}"

      {msg, path} when is_binary(msg) ->
        "#{path} — #{msg}"

      other ->
        inspect(other)
    end)
  end

  # --- catalog pass ---

  defp catalog_validate(%{"updateComponents" => %{"components" => components}}, opts) do
    catalog = Catalog.get()
    component_defs = Map.get(catalog, "components", %{})

    known_external =
      Keyword.get(opts, :known_component_ids, MapSet.new())

    batch_ids = MapSet.new(components, & &1["id"])
    all_known = MapSet.union(known_external, batch_ids)

    Enum.reduce_while(components, :ok, fn comp, _acc ->
      case check_component(comp, component_defs, all_known) do
        :ok -> {:cont, :ok}
        {:error, %{message: msg}} -> {:halt, {:error, "catalog: " <> msg}}
      end
    end)
  end

  defp catalog_validate(_envelope, _opts), do: :ok

  defp check_component(%{"component" => name} = comp, component_defs, all_known) do
    case Map.fetch(component_defs, name) do
      :error ->
        {:error,
         %{
           stage: :catalog,
           message: "unknown component '#{name}' (id=#{inspect(comp["id"])})"
         }}

      {:ok, def_schema} ->
        with :ok <- check_required(comp, def_schema, name) do
          check_child_refs(comp, all_known, name)
        end
    end
  end

  defp check_component(comp, _component_defs, _all_known) do
    {:error,
     %{stage: :catalog, message: "component missing 'component' key (id=#{inspect(comp["id"])})"}}
  end

  defp check_required(comp, def_schema, name) do
    required = leaf_required(def_schema)
    missing = Enum.reject(required, &Map.has_key?(comp, &1))

    case missing do
      [] ->
        :ok

      keys ->
        {:error,
         %{
           stage: :catalog,
           message: "#{name} ##{comp["id"]} missing required props: #{Enum.join(keys, ", ")}"
         }}
    end
  end

  # The MeldUI catalog defines components as `allOf: [common_refs..., {inline}]`.
  # The leaf inline object carries the component's own `required` array. Pluck it.
  defp leaf_required(%{"allOf" => items}) when is_list(items) do
    items
    |> Enum.find(fn item -> is_map(item) and not Map.has_key?(item, "$ref") end)
    |> case do
      nil -> []
      leaf -> Map.get(leaf, "required", []) -- ["component"]
    end
  end

  defp leaf_required(%{"required" => required}) when is_list(required), do: required
  defp leaf_required(_), do: []

  defp check_child_refs(comp, all_known, name) do
    refs = collect_child_refs(comp)
    missing = Enum.reject(refs, &MapSet.member?(all_known, &1))

    case missing do
      [] ->
        :ok

      ids ->
        {:error,
         %{
           stage: :catalog,
           message:
             "#{name} ##{comp["id"]} references unknown component ids: #{Enum.join(ids, ", ")}"
         }}
    end
  end

  # Walk the component object collecting strings sitting in commonly-named
  # child fields. Phase 3 heuristic — covers Column.children, Row.children,
  # Card.child, etc. without needing per-component schemas.
  defp collect_child_refs(comp) when is_map(comp) do
    Enum.flat_map(comp, fn
      {field, value} when field in @child_fields -> extract_strings(value)
      _ -> []
    end)
  end

  defp extract_strings(s) when is_binary(s), do: [s]
  defp extract_strings(list) when is_list(list), do: Enum.flat_map(list, &extract_strings/1)
  defp extract_strings(_), do: []
end
