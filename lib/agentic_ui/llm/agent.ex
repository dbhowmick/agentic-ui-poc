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
end
