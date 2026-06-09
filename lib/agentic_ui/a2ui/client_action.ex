defmodule AgenticUi.A2UI.ClientAction do
  @moduledoc """
  Inbound client→server A2UI v0.9 action payload.

  Matches the `A2uiClientAction` schema in `@a2ui/web_core` —
  the shape emitted by the renderer when a user triggers a component's
  `action.event` (button click, form submit, etc.):

      %{
        "name" => "submit",
        "surfaceId" => "form-name",
        "sourceComponentId" => "submit-btn",
        "timestamp" => "2026-06-10T12:34:56.000Z",
        "context" => %{"name" => "Dipayan"}
      }

  Phase 4 feeds this back into the LLM as a synthesised user-role turn —
  `Jido.AI.Agent` has no public API for injecting a tool_result for a tool
  the model did not call, so we wrap the action as a structured user message
  and let the system prompt teach the model to recognise it.
  """

  @enforce_keys [:name, :surface_id, :source_component_id, :timestamp, :context]
  defstruct [:name, :surface_id, :source_component_id, :timestamp, :context]

  @type t :: %__MODULE__{
          name: String.t(),
          surface_id: String.t(),
          source_component_id: String.t(),
          timestamp: String.t(),
          context: map()
        }

  @doc """
  Validate + cast an inbound payload off the wire (string keys).

  Returns `{:ok, %ClientAction{}}` or `{:error, reason}`. `reason` is a short
  human-readable binary suitable for surfacing back to the client over the
  channel's `"error"` event.
  """
  @spec cast(term()) :: {:ok, t()} | {:error, String.t()}
  def cast(%{
        "name" => name,
        "surfaceId" => sid,
        "sourceComponentId" => cid,
        "timestamp" => ts,
        "context" => ctx
      })
      when is_binary(name) and is_binary(sid) and is_binary(cid) and is_binary(ts) and is_map(ctx) do
    {:ok,
     %__MODULE__{
       name: name,
       surface_id: sid,
       source_component_id: cid,
       timestamp: ts,
       context: ctx
     }}
  end

  def cast(payload) when is_map(payload) do
    missing =
      ~w(name surfaceId sourceComponentId timestamp context)
      |> Enum.reject(&Map.has_key?(payload, &1))

    case missing do
      [] -> {:error, "a2ui_action: invalid field types"}
      keys -> {:error, "a2ui_action: missing fields #{Enum.join(keys, ", ")}"}
    end
  end

  def cast(_), do: {:error, "a2ui_action: payload must be a map"}

  @doc """
  Render the synthesised user-turn text that the LLM consumes.

  The `[a2ui_action]` prefix is the sentinel the system prompt teaches the
  model to recognise. Context is pretty-printed JSON so the model can read
  resolved binding values directly.
  """
  @spec to_user_content(t()) :: String.t()
  def to_user_content(%__MODULE__{} = a) do
    context_json =
      case Jason.encode(a.context, pretty: true) do
        {:ok, json} -> json
        _ -> inspect(a.context)
      end

    """
    [a2ui_action] surface=#{a.surface_id} source=#{a.source_component_id} name=#{a.name}
    context:
    #{context_json}
    """
    |> String.trim_trailing()
  end

  @doc """
  Render the raw action payload as a wire-shaped map for persistence in the
  `messages.tool_results` jsonb column. Keys match the inbound JSON so the
  frontend's TypeScript `A2uiClientAction` interface reads it unchanged.
  """
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = a) do
    %{
      "name" => a.name,
      "surfaceId" => a.surface_id,
      "sourceComponentId" => a.source_component_id,
      "timestamp" => a.timestamp,
      "context" => a.context
    }
  end
end
