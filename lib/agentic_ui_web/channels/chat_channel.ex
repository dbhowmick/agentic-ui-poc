defmodule AgenticUiWeb.ChatChannel do
  @moduledoc """
  One channel per chat conversation. Topic shape: `chat:<conversation_id>`.

  On join, ensures a `Jido.AgentServer` is running for this conversation under
  `AgenticUi.Jido`. On `"user_message"`, spawns a `Task` that calls
  `AgenticUi.LLM.Agent.ask_stream/3`, relays streaming signals to the client,
  and persists the user + assistant rows at turn boundaries.
  """
  use AgenticUiWeb, :channel
  require Logger

  alias AgenticUi.A2UI.ClientAction
  alias AgenticUi.Chat
  alias AgenticUi.Chat.Schemas.SurfaceSnapshot
  alias AgenticUi.LLM

  @impl true
  def join("chat:" <> conversation_id, _params, socket) do
    with {:uuid, {:ok, _}} <- {:uuid, Ecto.UUID.cast(conversation_id)},
         %_{} = conv <- Chat.get_conversation(conversation_id),
         {:ok, agent_pid} <- ensure_agent(conversation_id) do
      :ok = Phoenix.PubSub.subscribe(AgenticUi.PubSub, "chat:" <> conversation_id)

      socket =
        socket
        |> assign(:conversation_id, conversation_id)
        |> assign(:conversation, conv)
        |> assign(:agent_pid, agent_pid)

      send(self(), :after_join)
      {:ok, socket}
    else
      {:uuid, :error} -> {:error, %{reason: "invalid_conversation_id"}}
      nil -> {:error, %{reason: "conversation_not_found"}}
      {:error, e} -> {:error, %{reason: inspect(e)}}
    end
  end

  defp ensure_agent(id) do
    case AgenticUi.Jido.whereis(id) do
      nil ->
        initial_state = LLM.Agent.build_initial_state(Chat.list_messages(id))
        AgenticUi.Jido.start_agent(LLM.Agent, id: id, initial_state: initial_state)

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
    %{conversation_id: cid, agent_pid: agent_pid} = socket.assigns

    Task.start(fn -> run_turn(parent, cid, agent_pid, content) end)
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
        %{conversation_id: cid, agent_pid: agent_pid} = socket.assigns
        Task.start(fn -> run_action_turn(parent, cid, agent_pid, action) end)
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

  defp run_turn(channel_pid, cid, agent_pid, content) do
    _ = Chat.insert_message!(%{conversation_id: cid, role: "user", content: content})

    case LLM.Agent.ask_stream(agent_pid, content, tool_context: %{conversation_id: cid}) do
      {:ok, %{request: request, events: events}} ->
        {assistant_text, surface_ids} = relay_stream(events, channel_pid)
        _ = LLM.Agent.await(request, timeout: 60_000)

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

  # Same orchestration as `run_turn/4`, but the incoming content is synthesised
  # from a client-side A2UI action. The user row carries the structured action
  # payload in `tool_results` so the frontend can render it distinctly without
  # re-parsing the synthesised text.
  defp run_action_turn(channel_pid, cid, agent_pid, %ClientAction{} = action) do
    content = ClientAction.to_user_content(action)

    _ =
      Chat.insert_message!(%{
        conversation_id: cid,
        role: "user",
        content: content,
        tool_results: [ClientAction.to_payload(action)]
      })

    case LLM.Agent.ask_stream(agent_pid, content, tool_context: %{conversation_id: cid}) do
      {:ok, %{request: request, events: events}} ->
        {assistant_text, surface_ids} = relay_stream(events, channel_pid)
        _ = LLM.Agent.await(request, timeout: 60_000)

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

  # Iterate the Jido.AI runtime event stream. Returns `{accumulated_text,
  # surface_ids_created}` where `surface_ids_created` is the MapSet of surface
  # IDs that this turn's `create_surface` tool calls successfully created.
  # `update_components` / `update_data_model` don't count — only the originating
  # message of a surface owns the inline panel.
  defp relay_stream(events, channel_pid) do
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
