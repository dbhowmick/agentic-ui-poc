defmodule AgenticUi.LLM.Agent do
  @moduledoc """
  Conversation-level AI agent (ReAct strategy via `Jido.AI.Agent`).

  Phase 0: no tools, plain chat. Phase 2+ adds A2UI emission tools and embeds
  the MeldUI catalog into the system prompt.
  """
  use Jido.AI.Agent,
    name: "a2ui_agent",
    model: :default,
    tools: [],
    system_prompt: "You are the A2UI POC assistant. Be concise."

  alias AgenticUi.Chat.Schemas.Message
  alias Jido.AI.Context

  @doc """
  Builds an `initial_state` map suitable for passing to `AgenticUi.Jido.start_agent/2`,
  seeding the ReAct strategy's `Jido.AI.Context` from prior chat rows.

  Returns `%{}` when there are no seedable rows so the agent boots with a fresh
  context (the strategy will install one from the configured system prompt).
  """
  @spec build_initial_state([Message.t()]) :: map()
  def build_initial_state(messages) when is_list(messages) do
    messages
    |> Enum.flat_map(&row_to_message/1)
    |> case do
      [] -> %{}
      msgs -> %{context: Context.append_messages(Context.new(), msgs)}
    end
  end

  defp row_to_message(%Message{role: role, content: content})
       when role in ["user", "assistant"] and is_binary(content) and content != "" do
    [%{role: String.to_existing_atom(role), content: content}]
  end

  defp row_to_message(_), do: []
end
