defmodule AgenticUi.LLM.AgentStreamedJson do
  @moduledoc """
  Streamed-JSON mode counterpart of `AgenticUi.LLM.Agent` (Phase 5).

  Same model + same catalog, but no tools — the model emits A2UI envelopes as
  JSONL in its message body. `AgenticUiWeb.ChatChannel`'s per-turn relay tees
  content deltas through `AgenticUi.LLM.JsonlInterpreter`, which classifies
  complete lines as either prose or envelopes; envelopes are then handed to
  `AgenticUi.LLM.Tools.Emit.from_envelope/2` for the same validate → persist →
  broadcast pipeline the tool path uses.

  `jido_ai`'s `use Jido.AI.Agent` bakes `system_prompt`, `model`, and `tools`
  at compile time and offers no per-call override for those. Picking a module
  per conversation-mode is therefore the cleanest split — `AgenticUi.Jido`'s
  registry doesn't care which module a process implements.
  """

  @catalog_path Path.join(:code.priv_dir(:agentic_ui), "a2ui/catalog.json")
  @external_resource @catalog_path
  @catalog_json @catalog_path |> File.read!() |> AgenticUi.A2UI.Catalog.slim_json()
  @system_prompt AgenticUi.LLM.SystemPrompt.build(@catalog_json, mode: :streamed_json)

  use Jido.AI.Agent,
    name: "a2ui_agent_streamed_json",
    model: :default,
    tools: [],
    system_prompt: @system_prompt,
    llm_opts: [provider_options: [anthropic_prompt_cache: true]]

  defdelegate build_initial_state(messages), to: AgenticUi.LLM.Agent
end
