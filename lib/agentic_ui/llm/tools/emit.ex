defmodule AgenticUi.LLM.Tools.Emit do
  @moduledoc """
  Shared pipeline used by the four A2UI envelope tools.

  Each tool's `run/2` calls `emit/3` with its tool-name atom + parsed args +
  the `Jido.AI.Agent.ask_stream/3` `tool_context` map (which carries the
  conversation ID). The pipeline:

  1. Build the canonical A2UI v0.9 wire envelope.
  2. (For `:update_components`) Load the surface's known component IDs from
     the persisted snapshot so the validator can resolve cross-envelope refs.
  3. Validate (schema + catalog).
  4. Persist (`Chat.apply_envelope/2`) — DB before broadcast, so the client
     never renders an envelope the DB didn't record.
  5. Broadcast on `chat:<conversation_id>` via PubSub.
  6. Return `{:ok, %{acknowledged: true, surface_id: ...}}` for the model.

  On validation failure returns `{:error, "schema: ..."| "catalog: ..."}` so
  the LLM sees a recoverable tool result and self-corrects in the next step.
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
    surface_id = Envelope.surface_id(envelope)

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

  def emit(tool_name, _args, ctx) do
    Logger.error(
      "[A2UI tool] #{tool_name} called without :conversation_id in ctx=#{inspect(ctx)}"
    )

    {:error, "missing_conversation_context"}
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
