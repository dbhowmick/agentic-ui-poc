defmodule AgenticUi.LLM.Agent do
  @moduledoc """
  Conversation-level AI agent (ReAct strategy via `Jido.AI.Agent`).

  Phase 2: the four A2UI envelope tools (`CreateSurface`, `UpdateComponents`,
  `UpdateDataModel`, `DeleteSurface`) are wired, and the system prompt embeds
  the MeldUI catalog read from the vendored snapshot at compile time.

  Why compile-time: `Jido.AI.Agent`'s `system_prompt:` option only accepts
  compile-time literals (binaries, nil, false, or module attributes resolving
  to one). The vendored catalog under `priv/a2ui/catalog.json` is the build-time
  source of truth; `AgenticUi.A2UI.Catalog` still refreshes from the upstream
  URL at boot for use by the validator and tools (Phase 3+). To pick up an
  upstream catalog change in the system prompt, refresh the vendored file and
  rebuild (`@external_resource` triggers recompile when it changes).
  """

  @catalog_path Path.join(:code.priv_dir(:agentic_ui), "a2ui/catalog.json")
  @external_resource @catalog_path
  @catalog_json File.read!(@catalog_path)
  @system_prompt AgenticUi.LLM.SystemPrompt.build(@catalog_json)

  use Jido.AI.Agent,
    name: "a2ui_agent",
    model: :default,
    tools: [
      AgenticUi.LLM.Tools.CreateSurface,
      AgenticUi.LLM.Tools.UpdateComponents,
      AgenticUi.LLM.Tools.UpdateDataModel,
      AgenticUi.LLM.Tools.DeleteSurface
    ],
    system_prompt: @system_prompt

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
