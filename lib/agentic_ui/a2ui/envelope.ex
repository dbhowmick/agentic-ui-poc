defmodule AgenticUi.A2UI.Envelope do
  @moduledoc """
  Canonical A2UI v0.9 wire envelope construction + inspection.

  The four `Jido.Action` tools call `from_tool/2` to turn their parsed args into
  a wire-shaped envelope ready for validation, persistence, broadcast, and
  consumption by `@meldui/a2ui/vue`'s `processor.processMessages`.

  Wire shape (per A2UI v0.9 `server_to_client.json`):

      %{"version" => "v0.9",
        "createSurface" => %{"surfaceId" => ..., "catalogId" => ...}}

      %{"version" => "v0.9",
        "updateComponents" => %{"surfaceId" => ..., "components" => [...]}}

      %{"version" => "v0.9",
        "updateDataModel" => %{"surfaceId" => ..., "path" => ..., "value" => ...}}

      %{"version" => "v0.9",
        "deleteSurface" => %{"surfaceId" => ...}}
  """

  @version "v0.9"
  @catalog_id "https://meldui.dipayanb.com/a2ui/v1/catalog.json"

  @type tool_name :: :create_surface | :update_components | :update_data_model | :delete_surface
  @type envelope :: map()

  @spec catalog_id() :: String.t()
  def catalog_id, do: @catalog_id

  @spec version() :: String.t()
  def version, do: @version

  @spec from_tool(tool_name(), map()) :: envelope()
  def from_tool(:create_surface, %{surface_id: sid} = args) do
    %{
      "version" => @version,
      "createSurface" => %{
        "surfaceId" => sid,
        "catalogId" => Map.get(args, :catalog_id, @catalog_id)
      }
    }
  end

  def from_tool(:update_components, %{surface_id: sid, components: components}) do
    %{
      "version" => @version,
      "updateComponents" => %{
        "surfaceId" => sid,
        "components" => Enum.map(components, &stringify_keys/1)
      }
    }
  end

  def from_tool(:update_data_model, %{surface_id: sid} = args) do
    body =
      %{"surfaceId" => sid}
      |> maybe_put("path", Map.get(args, :path))
      |> maybe_put("value", Map.get(args, :value))

    %{"version" => @version, "updateDataModel" => body}
  end

  def from_tool(:delete_surface, %{surface_id: sid}) do
    %{"version" => @version, "deleteSurface" => %{"surfaceId" => sid}}
  end

  @doc "Returns the message kind atom for an envelope."
  @spec message_type(envelope()) :: tool_name() | nil
  def message_type(%{"createSurface" => _}), do: :create_surface
  def message_type(%{"updateComponents" => _}), do: :update_components
  def message_type(%{"updateDataModel" => _}), do: :update_data_model
  def message_type(%{"deleteSurface" => _}), do: :delete_surface
  def message_type(_), do: nil

  @doc "Returns the surface_id of an envelope, or nil for malformed envelopes."
  @spec surface_id(envelope()) :: String.t() | nil
  def surface_id(%{"createSurface" => %{"surfaceId" => s}}), do: s
  def surface_id(%{"updateComponents" => %{"surfaceId" => s}}), do: s
  def surface_id(%{"updateDataModel" => %{"surfaceId" => s}}), do: s
  def surface_id(%{"deleteSurface" => %{"surfaceId" => s}}), do: s
  def surface_id(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
