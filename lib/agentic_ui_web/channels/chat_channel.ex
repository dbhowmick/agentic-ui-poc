defmodule AgenticUiWeb.ChatChannel do
  @moduledoc """
  One channel per chat conversation. Topic shape: `chat:<conversation_id>`.

  On join, ensures a `Jido.AgentServer` is running for this conversation under
  `AgenticUi.Jido`. The agent module is picked from the conversation's `mode`
  field — `AgenticUi.LLM.Agent` for `tool_calls`, `AgenticUi.LLM.AgentStreamedJson`
  for `streamed_json`. On `"user_message"`, spawns a `Task` that calls
  `ask_stream/3` on the per-mode module, relays streaming signals to the
  client, and persists the user + assistant rows at turn boundaries.

  In `:streamed_json` mode the agent has no tools registered and writes A2UI
  envelopes as JSONL in its message body. Per-`:llm_delta` `:content` chunks
  are teed through `AgenticUi.LLM.JsonlInterpreter`, which classifies complete
  lines as prose vs. envelopes. Prose is forwarded as `assistant_token`;
  envelopes go through `AgenticUi.LLM.Tools.Emit.from_envelope/2` (the same
  validate → persist → broadcast pipeline the tool path uses).
  """
  use AgenticUiWeb, :channel
  require Logger

  alias AgenticUi.A2UI.{ClientAction, Envelope}
  alias AgenticUi.Chat
  alias AgenticUi.Chat.Schemas.SurfaceSnapshot
  alias AgenticUi.LLM
  alias AgenticUi.LLM.JsonlInterpreter
  alias AgenticUi.LLM.Tools.Emit

  @impl true
  def join("chat:" <> conversation_id, _params, socket) do
    with {:uuid, {:ok, _}} <- {:uuid, Ecto.UUID.cast(conversation_id)},
         %_{} = conv <- Chat.get_conversation(conversation_id),
         agent_mod = agent_module(conv.mode),
         {:ok, agent_pid} <- ensure_agent(conversation_id, agent_mod) do
      :ok = Phoenix.PubSub.subscribe(AgenticUi.PubSub, "chat:" <> conversation_id)

      socket =
        socket
        |> assign(:conversation_id, conversation_id)
        |> assign(:conversation, conv)
        |> assign(:agent_pid, agent_pid)
        |> assign(:agent_mod, agent_mod)
        |> assign(:mode, conv.mode)

      send(self(), :after_join)
      {:ok, socket}
    else
      {:uuid, :error} -> {:error, %{reason: "invalid_conversation_id"}}
      nil -> {:error, %{reason: "conversation_not_found"}}
      {:error, e} -> {:error, %{reason: inspect(e)}}
    end
  end

  defp agent_module("streamed_json"), do: LLM.AgentStreamedJson
  defp agent_module(_), do: LLM.Agent

  defp ensure_agent(id, agent_mod) do
    case AgenticUi.Jido.whereis(id) do
      nil ->
        initial_state = agent_mod.build_initial_state(Chat.list_messages(id))
        AgenticUi.Jido.start_agent(agent_mod, id: id, initial_state: initial_state)

      pid ->
        {:ok, pid}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    cid = socket.assigns.conversation_id
    push(socket, "history", %{messages: Chat.list_messages(cid)})
    push(socket, "a2ui_replay", %{surfaces: replay_payload(cid)})
    {:noreply, socket}
  end

  def handle_info({:assistant_token, delta}, socket) do
    push(socket, "assistant_token", %{delta: delta})
    {:noreply, socket}
  end

  def handle_info({:a2ui_envelope, envelope}, socket) do
    push(socket, "a2ui_envelope", envelope)
    {:noreply, socket}
  end

  def handle_info({:assistant_done, _cid}, socket) do
    push(socket, "assistant_done", %{})
    {:noreply, socket}
  end

  def handle_info({:llm_error, reason}, socket) do
    push(socket, "error", %{message: inspect(reason)})
    {:noreply, socket}
  end

  @impl true
  def handle_in("user_message", %{"content" => content}, socket)
      when is_binary(content) and content != "" do
    parent = self()
    %{conversation_id: cid, agent_pid: agent_pid, agent_mod: mod, mode: mode} = socket.assigns

    Task.start(fn -> run_turn(parent, cid, agent_pid, mod, mode, content) end)
    {:reply, :ok, socket}
  end

  # Client → server A2UI action (user clicks a button, submits a form, etc.).
  # The renderer (`@a2ui/web_core` via `@meldui/a2ui/vue`) emits the standard
  # v0.9 `A2uiClientAction` shape. We synthesise a user-role turn from it and
  # feed it through the same `ask_stream` pipeline as a typed user_message,
  # closing the round-trip.
  def handle_in("a2ui_action", payload, socket) do
    case ClientAction.cast(payload) do
      {:ok, %ClientAction{} = action} ->
        parent = self()
        %{conversation_id: cid, agent_pid: agent_pid, agent_mod: mod, mode: mode} = socket.assigns
        Task.start(fn -> run_action_turn(parent, cid, agent_pid, mod, mode, action) end)
        {:reply, :ok, socket}

      {:error, reason} ->
        Logger.warning("a2ui_action rejected: #{reason} payload=#{inspect(payload)}")
        push(socket, "error", %{message: reason})
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("a2ui_error", payload, socket) do
    Logger.warning("a2ui_error from client: #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  # --- per-turn orchestration ---

  defp run_turn(channel_pid, cid, agent_pid, mod, mode, content) do
    _ = Chat.insert_message!(%{conversation_id: cid, role: "user", content: content})

    case mod.ask_stream(agent_pid, content, tool_context: %{conversation_id: cid}) do
      {:ok, %{request: request, events: events}} ->
        {assistant_text, surface_ids} = relay_stream(events, channel_pid, cid, mode)
        _ = mod.await(request, timeout: 60_000)

        _ =
          Chat.insert_message!(%{
            conversation_id: cid,
            role: "assistant",
            content: assistant_text,
            surface_ids: MapSet.to_list(surface_ids)
          })

        send(channel_pid, {:assistant_done, cid})

      {:error, reason} ->
        send(channel_pid, {:llm_error, reason})
    end
  end

  # Same orchestration as `run_turn/6`, but the incoming content is synthesised
  # from a client-side A2UI action. The user row carries the structured action
  # payload in `tool_results` so the frontend can render it distinctly without
  # re-parsing the synthesised text.
  defp run_action_turn(channel_pid, cid, agent_pid, mod, mode, %ClientAction{} = action) do
    content = ClientAction.to_user_content(action)

    _ =
      Chat.insert_message!(%{
        conversation_id: cid,
        role: "user",
        content: content,
        tool_results: [ClientAction.to_payload(action)]
      })

    case mod.ask_stream(agent_pid, content, tool_context: %{conversation_id: cid}) do
      {:ok, %{request: request, events: events}} ->
        {assistant_text, surface_ids} = relay_stream(events, channel_pid, cid, mode)
        _ = mod.await(request, timeout: 60_000)

        _ =
          Chat.insert_message!(%{
            conversation_id: cid,
            role: "assistant",
            content: assistant_text,
            surface_ids: MapSet.to_list(surface_ids)
          })

        send(channel_pid, {:assistant_done, cid})

      {:error, reason} ->
        send(channel_pid, {:llm_error, reason})
    end
  end

  # Tool-calls mode: assistant text is the only content. Surface IDs come from
  # `create_surface` tool completions.
  defp relay_stream(events, channel_pid, _cid, "tool_calls") do
    Enum.reduce(events, {"", MapSet.new()}, fn event, {text, sids} ->
      log_tool_event(event)

      sids =
        case extract_created_surface(event) do
          {:ok, sid} -> MapSet.put(sids, sid)
          :none -> sids
        end

      case extract_delta(event) do
        {:content, delta} ->
          send(channel_pid, {:assistant_token, delta})
          {text <> delta, sids}

        _other ->
          {text, sids}
      end
    end)
  end

  # Streamed-JSON mode: content deltas are fed into a JsonlInterpreter and
  # classified into prose vs. envelopes. Prose is forwarded to the chat panel
  # as assistant_token AND accumulated for the persisted assistant row.
  # Envelopes go through Emit.from_envelope/2 (validate → persist → broadcast).
  # We flush the interpreter on stream end so a trailing unterminated line is
  # still processed.
  defp relay_stream(events, channel_pid, cid, "streamed_json") do
    {text, sids, state} =
      Enum.reduce(
        events,
        {"", MapSet.new(), JsonlInterpreter.new()},
        fn event, {text, sids, state} ->
          case extract_delta(event) do
            {:content, delta} ->
              {state, emissions} = JsonlInterpreter.feed(state, delta)
              {text2, sids2} = drain_emissions(emissions, channel_pid, cid, text, sids)
              {text2, sids2, state}

            _other ->
              {text, sids, state}
          end
        end
      )

    {text2, sids2} = drain_emissions(JsonlInterpreter.flush(state), channel_pid, cid, text, sids)
    {text2, sids2}
  end

  defp drain_emissions(emissions, channel_pid, cid, text0, sids0) do
    Enum.reduce(emissions, {text0, sids0}, fn
      {:text, txt}, {text, sids} ->
        send(channel_pid, {:assistant_token, txt})
        {text <> txt, sids}

      {:envelope, env}, {text, sids} ->
        {text, apply_envelope_result(Emit.from_envelope(env, cid), env, sids, channel_pid)}
    end)
  end

  defp apply_envelope_result({:ok, %{surface_id: sid}}, env, sids, _channel_pid) do
    case Envelope.message_type(env) do
      :create_surface when is_binary(sid) -> MapSet.put(sids, sid)
      _ -> sids
    end
  end

  defp apply_envelope_result({:error, reason}, _env, sids, channel_pid) do
    send(channel_pid, {:llm_error, reason})
    sids
  end

  # A successful `create_surface` tool completion looks like:
  #   %{kind: :tool_completed, tool_name: "create_surface",
  #     data: %{result: {:ok, %{surface_id: sid, ...}, _effects},
  #             tool_name: "create_surface", ...}}
  # Match both the 3-tuple `{status, value, effects}` (Jido canonical) and the
  # 2-tuple `{status, value}` for defensiveness against future shape drift.
  defp extract_created_surface(%{
         kind: :tool_completed,
         tool_name: "create_surface",
         data: %{result: result}
       }) do
    case result do
      {:ok, %{surface_id: sid}, _effects} when is_binary(sid) -> {:ok, sid}
      {:ok, %{surface_id: sid}} when is_binary(sid) -> {:ok, sid}
      _ -> :none
    end
  end

  defp extract_created_surface(_), do: :none

  defp extract_delta(%{kind: :llm_delta, data: %{delta: delta} = data})
       when is_binary(delta) and delta != "" do
    case Map.get(data, :chunk_type, :content) do
      :content -> {:content, delta}
      _ -> :ignore
    end
  end

  defp extract_delta(_), do: :ignore

  defp log_tool_event(%{kind: :tool_started, tool_name: name, data: data}),
    do: Logger.debug("[A2UI tool] started #{name} data=#{inspect(data)}")

  defp log_tool_event(%{kind: :tool_completed, tool_name: name, data: data}),
    do: Logger.debug("[A2UI tool] completed #{name} data=#{inspect(data)}")

  defp log_tool_event(_), do: :ok

  defp replay_payload(conversation_id) do
    conversation_id
    |> Chat.list_surface_snapshots()
    |> Enum.map(fn %SurfaceSnapshot{} = s ->
      %{
        surface_id: s.surface_id,
        envelope_log: s.envelope_log || [],
        data_model: s.data_model || %{},
        updated_at: s.updated_at
      }
    end)
  end
end
