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

  alias AgenticUi.Chat
  alias AgenticUi.LLM

  @impl true
  def join("chat:" <> conversation_id, _params, socket) do
    with {:uuid, {:ok, _}} <- {:uuid, Ecto.UUID.cast(conversation_id)},
         %_{} = conv <- Chat.get_conversation(conversation_id),
         {:ok, agent_pid} <- ensure_agent(conversation_id) do
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
    push(socket, "history", %{messages: Chat.list_messages(socket.assigns.conversation_id)})
    {:noreply, socket}
  end

  def handle_info({:assistant_token, delta}, socket) do
    push(socket, "assistant_token", %{delta: delta})
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

  # Phase 0 stubs — wired in later phases.
  def handle_in("a2ui_action", payload, socket) do
    Logger.info("a2ui_action (stub): #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  def handle_in("a2ui_error", payload, socket) do
    Logger.warning("a2ui_error from client: #{inspect(payload)}")
    {:reply, :ok, socket}
  end

  # --- per-turn orchestration ---

  defp run_turn(channel_pid, cid, agent_pid, content) do
    _ = Chat.insert_message!(%{conversation_id: cid, role: "user", content: content})

    case LLM.Agent.ask_stream(agent_pid, content) do
      {:ok, %{request: request, events: events}} ->
        assistant_text = relay_stream(events, channel_pid)
        _ = LLM.Agent.await(request, timeout: 60_000)

        _ =
          Chat.insert_message!(%{
            conversation_id: cid,
            role: "assistant",
            content: assistant_text
          })

        send(channel_pid, {:assistant_done, cid})

      {:error, reason} ->
        send(channel_pid, {:llm_error, reason})
    end
  end

  # Iterate the Jido.AI runtime event stream and forward content deltas to the
  # channel. Returns the accumulated assistant text. See
  # `Jido.AI.Runtime.Event` for the canonical envelope; per-turn we care about
  # `:llm_delta` (chunk_type :content) for streaming text. Thinking deltas
  # are dropped here.
  defp relay_stream(events, channel_pid) do
    Enum.reduce(events, "", fn event, acc ->
      case extract_delta(event) do
        {:content, delta} ->
          send(channel_pid, {:assistant_token, delta})
          acc <> delta

        _other ->
          acc
      end
    end)
  end

  defp extract_delta(%{kind: :llm_delta, data: %{delta: delta} = data})
       when is_binary(delta) and delta != "" do
    case Map.get(data, :chunk_type, :content) do
      :content -> {:content, delta}
      _ -> :ignore
    end
  end

  defp extract_delta(_), do: :ignore
end
