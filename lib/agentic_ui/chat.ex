defmodule AgenticUi.Chat do
  @moduledoc """
  Chat context: conversation + message + surface_snapshot persistence.

  All Repo writes for chat data go through this module so the channel and
  controller layers stay thin.
  """

  import Ecto.Query

  alias AgenticUi.A2UI.Envelope
  alias AgenticUi.Chat.Schemas.{Conversation, Message, SurfaceSnapshot}
  alias AgenticUi.Repo

  # --- Conversations ---

  @spec list_conversations(pos_integer()) :: [Conversation.t()]
  def list_conversations(limit \\ 50) do
    Conversation
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_conversation(binary()) :: Conversation.t() | nil
  def get_conversation(id), do: Repo.get(Conversation, id)

  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  # --- Messages (called from the channel's per-turn Task) ---

  @spec list_messages(binary()) :: [Message.t()]
  def list_messages(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @spec insert_message!(map()) :: Message.t()
  def insert_message!(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert!()
  end

  # --- Surface snapshots ---

  @spec list_surface_snapshots(binary()) :: [SurfaceSnapshot.t()]
  def list_surface_snapshots(conversation_id) do
    SurfaceSnapshot
    |> where(conversation_id: ^conversation_id)
    |> Repo.all()
  end

  @spec get_surface_snapshot(binary(), String.t()) :: SurfaceSnapshot.t() | nil
  def get_surface_snapshot(conversation_id, surface_id) do
    Repo.get_by(SurfaceSnapshot, conversation_id: conversation_id, surface_id: surface_id)
  end

  @doc """
  Apply an A2UI envelope to the `surface_snapshots` table.

  - `createSurface` → insert a new row (errors if surface already exists, per spec)
  - `updateComponents` → append to `envelope_log`
  - `updateDataModel` → append to `envelope_log` AND apply the path/value mutation to `data_model`
  - `deleteSurface` → delete the row

  Called from inside the Jido tool actions. Per-conversation turns run
  serially through one `Jido.AgentServer` so no concurrent writes are expected
  for a single surface.
  """
  @spec apply_envelope(binary(), map()) :: {:ok, SurfaceSnapshot.t() | nil} | {:error, term()}
  def apply_envelope(conversation_id, envelope) when is_map(envelope) do
    surface_id = Envelope.surface_id(envelope)
    type = Envelope.message_type(envelope)
    do_apply(type, conversation_id, surface_id, envelope)
  end

  defp do_apply(:create_surface, cid, sid, envelope) do
    case get_surface_snapshot(cid, sid) do
      nil ->
        %SurfaceSnapshot{}
        |> SurfaceSnapshot.changeset(%{
          conversation_id: cid,
          surface_id: sid,
          envelope_log: [envelope],
          data_model: %{}
        })
        |> Repo.insert()

      _existing ->
        {:error, :surface_already_exists}
    end
  end

  defp do_apply(:update_components, cid, sid, envelope) do
    case get_surface_snapshot(cid, sid) do
      nil ->
        {:error, :surface_not_found}

      %SurfaceSnapshot{} = snap ->
        snap
        |> SurfaceSnapshot.changeset(%{envelope_log: snap.envelope_log ++ [envelope]})
        |> Repo.update()
    end
  end

  defp do_apply(:update_data_model, cid, sid, envelope) do
    case get_surface_snapshot(cid, sid) do
      nil ->
        {:error, :surface_not_found}

      %SurfaceSnapshot{} = snap ->
        body = envelope["updateDataModel"]
        path = Map.get(body, "path", "/")
        value = Map.get(body, "value")
        new_data_model = apply_data_model_patch(snap.data_model || %{}, path, value)

        snap
        |> SurfaceSnapshot.changeset(%{
          envelope_log: snap.envelope_log ++ [envelope],
          data_model: new_data_model
        })
        |> Repo.update()
    end
  end

  defp do_apply(:delete_surface, cid, sid, _envelope) do
    case get_surface_snapshot(cid, sid) do
      nil -> {:ok, nil}
      %SurfaceSnapshot{} = snap -> Repo.delete(snap)
    end
  end

  defp do_apply(nil, _cid, _sid, _envelope), do: {:error, :unknown_envelope_type}

  # Apply a v0.9 updateDataModel patch in-process. JSON Pointer paths like
  # "/users/0/name". An omitted/empty value at a path means delete that key.
  @spec apply_data_model_patch(map(), String.t(), term()) :: map()
  def apply_data_model_patch(model, path, value) when path in ["", "/", nil] do
    case value do
      nil -> %{}
      v when is_map(v) -> v
      _ -> model
    end
  end

  def apply_data_model_patch(model, "/" <> rest, value) when is_binary(rest) do
    keys = String.split(rest, "/")

    case value do
      nil -> remove_in(model, keys)
      _ -> put_in_nested(model, keys, value)
    end
  end

  defp put_in_nested(map, [key], value) when is_map(map), do: Map.put(map, key, value)

  defp put_in_nested(map, [key | rest], value) when is_map(map) do
    inner = Map.get(map, key, %{})
    inner = if is_map(inner), do: inner, else: %{}
    Map.put(map, key, put_in_nested(inner, rest, value))
  end

  defp remove_in(map, [key]) when is_map(map), do: Map.delete(map, key)

  defp remove_in(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      inner when is_map(inner) -> Map.put(map, key, remove_in(inner, rest))
      _ -> map
    end
  end

  defp remove_in(map, _path), do: map

  @doc """
  Returns the set of component IDs already known on a surface — derived from
  the persisted envelope_log's `updateComponents` payloads. Used by the
  Validator to resolve cross-envelope child refs.
  """
  @spec known_component_ids(binary(), String.t()) :: MapSet.t()
  def known_component_ids(conversation_id, surface_id) do
    case get_surface_snapshot(conversation_id, surface_id) do
      nil ->
        MapSet.new()

      %SurfaceSnapshot{envelope_log: log} ->
        log
        |> List.wrap()
        |> Enum.flat_map(fn
          %{"updateComponents" => %{"components" => components}} ->
            Enum.map(components, & &1["id"])

          _ ->
            []
        end)
        |> MapSet.new()
    end
  end
end
