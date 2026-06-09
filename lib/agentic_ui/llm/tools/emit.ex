defmodule AgenticUi.LLM.Tools.Emit do
  @moduledoc """
  Shared envelope pipeline used by both emission modes.

  In `:tool_calls` mode each of the four `Jido.Action` tools' `run/2` calls
  `emit/3` with its tool-name atom + parsed args + the
  `Jido.AI.Agent.ask_stream/3` `tool_context` map (which carries the
  conversation ID). In `:streamed_json` mode the channel's per-turn relay
  hands already-built envelopes parsed from the assistant's JSONL stream to
  `from_envelope/2`. Both routes converge on `do_emit/4`:

  1. (For `:update_components`) Load the surface's known component IDs from
     the persisted snapshot so the validator can resolve cross-envelope refs.
  2. Validate (schema + catalog).
  3. Persist (`Chat.apply_envelope/2`) — DB before broadcast, so the client
     never renders an envelope the DB didn't record.
  4. Broadcast on `chat:<conversation_id>` via PubSub.
  5. Return `{:ok, %{acknowledged: true, surface_id: ...}}`.

  On validation failure returns `{:error, "schema: ..." | "catalog: ..."}` —
  shaped for direct consumption as either a tool result the LLM sees or an
  error event the channel pushes to the client.
  """

  require Logger
  alias AgenticUi.A2UI.{Envelope, Validator}
  alias AgenticUi.Chat

  @type tool_name :: Envelope.tool_name()

  # Anthropic's parallel tool calls let `update_components` race ahead of
  # `create_surface` within a single assistant turn. The retry window absorbs
  # that race so the model doesn't see a spurious :surface_not_found and the
  # client doesn't receive envelopes out of dependency order.
  @race_retry_attempts 10
  @race_retry_delay_ms 50

  @spec emit(tool_name(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def emit(tool_name, args, %{conversation_id: cid}) when is_binary(cid) do
    envelope = Envelope.from_tool(tool_name, args)
    do_emit(tool_name, envelope, Envelope.surface_id(envelope), cid)
  end

  def emit(tool_name, _args, ctx) do
    Logger.error(
      "[A2UI tool] #{tool_name} called without :conversation_id in ctx=#{inspect(ctx)}"
    )

    {:error, "missing_conversation_context"}
  end

  @doc """
  Streamed-JSON entry point. Takes an already-built wire envelope (parsed out
  of the assistant's JSONL stream) and runs it through the same pipeline as a
  tool-call envelope. Returns `{:error, "unknown_envelope_type"}` if the map
  doesn't carry one of the four recognised kind keys.
  """
  @spec from_envelope(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def from_envelope(envelope, cid) when is_map(envelope) and is_binary(cid) do
    case Envelope.message_type(envelope) do
      nil ->
        {:error, "unknown_envelope_type"}

      tool_name ->
        do_emit(tool_name, envelope, Envelope.surface_id(envelope), cid)
    end
  end

  defp do_emit(tool_name, envelope, surface_id, cid) do
    opts =
      case tool_name do
        :update_components ->
          [known_component_ids: Chat.known_component_ids(cid, surface_id)]

        _ ->
          []
      end

    with :ok <- Validator.validate(envelope, opts),
         {:ok, _snapshot_or_nil} <- persist_with_race_retry(tool_name, cid, envelope) do
      Phoenix.PubSub.broadcast(
        AgenticUi.PubSub,
        "chat:" <> cid,
        {:a2ui_envelope, envelope}
      )

      {:ok, %{acknowledged: true, surface_id: surface_id}}
    else
      {:error, reason} when is_binary(reason) ->
        Logger.warning("[A2UI tool] #{tool_name} rejected: #{reason}")
        {:error, reason}

      {:error, reason} ->
        msg = "persistence_failed: " <> inspect(reason)
        Logger.warning("[A2UI tool] #{tool_name} #{msg}")
        {:error, msg}
    end
  end

  defp persist_with_race_retry(tool_name, cid, envelope)
       when tool_name in [:update_components, :update_data_model] do
    do_persist_with_retry(cid, envelope, @race_retry_attempts)
  end

  defp persist_with_race_retry(_tool_name, cid, envelope) do
    Chat.apply_envelope(cid, envelope)
  end

  defp do_persist_with_retry(cid, envelope, attempts_left) do
    case Chat.apply_envelope(cid, envelope) do
      {:error, :surface_not_found} when attempts_left > 1 ->
        Process.sleep(@race_retry_delay_ms)
        do_persist_with_retry(cid, envelope, attempts_left - 1)

      other ->
        other
    end
  end
end
