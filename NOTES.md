# Implementation notes

Findings discovered while building the POC. Mostly things that aren't obvious from a casual read of the dependency docs, kept here so the blog post has accurate ammunition.

## jido_ai streaming event shape

`MyAgent.ask_stream/3` returns `{:ok, %{request: handle, events: enumerable}}`. The enumerable yields `Jido.AI.Reasoning.ReAct.Event` structs (a thin compatibility wrapper around `Jido.AI.Runtime.Event`). Each event has:

```
%{
  id: "evt_…",
  seq: integer,
  at_ms: integer,
  run_id: string,
  request_id: string,
  iteration: integer,
  kind: atom,                  # one of the @kind_values below
  llm_call_id: string | nil,
  tool_call_id: string | nil,
  tool_name: string | nil,
  data: map                    # payload, varies per kind
}
```

The full kind set (`Jido.AI.Runtime.Event.kinds/0`):

```
:request_started, :llm_started, :llm_delta, :llm_completed,
:output_started, :output_validated, :output_repair, :output_failed,
:tool_started, :tool_completed,
:checkpoint, :request_completed, :request_failed, :request_cancelled
```

### Per-token text deltas

`%{kind: :llm_delta, data: %{delta: "…", chunk_type: :content | :thinking | …}}` — only `:content` chunks are user-visible assistant text. We pipe these to `assistant_token`.

### Tool completions

`%{kind: :tool_completed, tool_name: "create_surface", data: %{result: {:ok, %{surface_id: "..."}, _effects}}}` — the runner emits both the 3-tuple `{status, value, effects}` (Jido canonical) and the 2-tuple `{status, value}` from older code paths. Match both for defensiveness.

### Usage rollup (per turn)

`%{kind: :request_completed, data: %{usage: usage_map, result: ..., termination_reason: ...}}` carries the **end-of-turn** rollup. The usage map is normalized by `Jido.AI.Usage.normalize/1` to atom keys:

```
%{
  input_tokens: integer,
  output_tokens: integer,
  total_tokens: integer,
  cache_creation_input_tokens: integer,   # prompt-cache *write* (first hit)
  cache_read_input_tokens: integer        # prompt-cache *read* (subsequent hits)
}
```

Provider-specific extras (e.g. `reasoning_tokens`, cost fields) pass through verbatim. Anthropic distinguishes `cache_creation_input_tokens` (the write that built the cache for a system-prompt prefix) from `cache_read_input_tokens` (the hits on subsequent turns) — both are tracked separately so the blog can show the cache earning its keep across multi-turn conversations.

`:llm_completed` events also exist with per-LLM-call usage in `data.usage`, but they fire once per inner LLM call inside a ReAct loop (tools cause multiple). For surface-level "what did this turn cost" we use the `:request_completed` rollup; the inner events would be needed for finer-grained breakdowns (skipped for the POC).

### Where this is consumed

`AgenticUiWeb.ChatChannel.relay_stream/4` iterates the events enumerable. Phase 6 adds an `extract_usage/1` matcher to capture the final `:request_completed` payload and persists it on the assistant `messages` row alongside a wall-clock `latency_ms`.
