# A2UI POC — Implementation Plan

## 1. Goal

Build an end-to-end testbed for [MeldUI's A2UI](https://meldui.dipayanb.com/docs/a2ui/) integration. A user chats with Anthropic Claude in a Vue SPA; the model streams [A2UI v0.9](https://a2ui.org/specification/v0.9-a2ui/) messages through a Phoenix backend that orchestrates the LLM loop; the frontend renders those messages live against the MeldUI catalog. Button clicks and form inputs in the rendered UI flow back to the LLM as `action` events, closing the loop.

Two deliverables:

1. A working POC that exercises the full A2UI surface area of MeldUI's catalog.
2. A blog-ready codebase — readable, narratable, with a few interesting beats (tool-call vs streamed-JSON modes, schema validation gate, the action round-trip).

Non-goals: auth, multi-tenancy, multi-provider abstraction, background work.

## 2. Architectural choices (decided)

| Choice | Decision | Why |
|---|---|---|
| LLM layer | **Jido + jido_ai** | Use it as the agent runtime; the blog covers Jido as a topic alongside A2UI. |
| A2UI emission mode | **Both, toggleable** — tool-call mode and streamed-JSON mode | Tool-call mode is the clean production path; streamed-JSON exercises the protocol's progressive-rendering intent. Comparison is blog material. |
| Transport | **Phoenix Channels** (one WebSocket) | Bidirectional, `phoenix` npm pkg already installed, fits A2UI's action loop natively. |
| Persistence | **Conversations + surfaces** in Postgres via Ecto | Reload-safe, shareable, makes the demo feel real. |
| Renderer | **`@meldui/a2ui` + `@a2ui/web_core`** on the Vue side | `@meldui/a2ui@0.1.0` ships the catalog and depends on `@a2ui/web_core` for rendering. Working today. |

## 3. High-level architecture

```
┌────────────────────────────┐                ┌───────────────────────────────────────┐
│  Vue SPA (frontend/)       │                │  Phoenix (lib/agentic_ui*)            │
│                            │                │                                       │
│  ChatView                  │   Channel      │  AgenticUiWeb.UserSocket              │
│  ├─ MessageList            │ ◄────────────► │   └─ ChatChannel "chat:<conv_id>"     │
│  ├─ Composer               │   WS           │        │                              │
│  └─ A2UISurface (per msg)  │                │        │ ensure_agent + ask_stream    │
│       └─ @a2ui/web_core    │                │        ▼                              │
│           + MeldUI catalog │                │   Jido.AgentServer per conv           │
│                            │                │   (under AgenticUi.Jido — Registry +  │
└────────────────────────────┘                │    DynamicSupervisor from `use Jido`) │
                                              │        │                              │
                                              │        ▼                              │
                                              │   AgenticUi.LLM.Agent (Jido.AI.Agent) │
                                              │        │  tools: create_surface, ... │
                                              │        ▼                              │
                                              │   Anthropic Claude (via req_llm)      │
                                              │                                       │
                                              │   AgenticUi.A2UI.Validator (schema)   │
                                              │   AgenticUi.Chat + Repo (Ecto)        │
                                              └───────────────────────────────────────┘
```

The Channel is the boundary. Per-conversation orchestration uses `Jido.AgentServer` — Jido's built-in `DynamicSupervisor` + `Registry` (mounted via `AgenticUi.Jido`'s `use Jido, otp_app: :agentic_ui`) own the lifecycle and addressing. The channel's per-turn `Task` consumes the streaming events from `LLM.Agent.ask_stream/3` and writes the user + assistant message rows at turn boundaries.

## 4. Backend design

### 4.1 Dependencies to add (`mix.exs`)

```elixir
{:jido, "~> 2.3"},
{:jido_ai, "~> 2.2"},
{:req_llm, "~> 1.15"},         # transitive via jido_ai, pinned for clarity
{:ex_json_schema, "~> 0.11"}   # validate A2UI envelopes
```

Anthropic credentials via `ANTHROPIC_API_KEY` (read in `runtime.exs`).

### 4.2 Module layout

```
lib/agentic_ui/
├── jido.ex                      `use Jido, otp_app: :agentic_ui` — brings the
│                                DynamicSupervisor + Registry that own
│                                Jido.AgentServer processes (one per conv).
├── chat.ex                      Context module — list_conversations,
│                                insert_message!, list_messages, ...
├── chat/
│   └── schemas/
│       ├── conversation.ex      Ecto schema: id, title, mode, model
│       ├── message.ex           Ecto schema: role, content, tool_calls, tool_results
│       └── surface_snapshot.ex  Ecto schema: composite PK (conversation_id, surface_id)
├── llm/
│   ├── agent.ex                 Jido.AI.Agent definition (system prompt, tools, model)
│   ├── system_prompt.ex         builds the prompt, embeds catalog JSON (Phase 2+)
│   └── tools/                   Jido.Action modules — A2UI envelope emitters (Phase 3+)
│       ├── create_surface.ex
│       ├── update_components.ex
│       ├── update_data_model.ex
│       └── delete_surface.ex
└── a2ui/                        Phase 2+
    ├── catalog.ex               loads + caches the MeldUI catalog JSON (Req)
    ├── envelope.ex              typed wrappers + JSON encoding
    └── validator.ex             validates an envelope against the A2UI v0.9 schema

lib/agentic_ui_web/
├── channels/
│   ├── user_socket.ex
│   └── chat_channel.ex
└── controllers/
    └── conversations_controller.ex   JSON API: list / create / get
```

Supervision: add `AgenticUi.Jido` as a child in `application.ex`. No custom Registry or DynamicSupervisor — Jido provides both.

### 4.3 The Jido agent

Two modules, both tiny. `AgenticUi.Jido` brings the runtime; `AgenticUi.LLM.Agent` defines the agent behavior.

```elixir
defmodule AgenticUi.Jido do
  use Jido, otp_app: :agentic_ui   # supplies DynamicSupervisor + Registry
end

defmodule AgenticUi.LLM.Agent do
  use Jido.AI.Agent,
    name: "a2ui_agent",
    model: :default,                # alias resolved via :jido_ai model_aliases
    tools: [
      AgenticUi.LLM.Tools.CreateSurface,
      AgenticUi.LLM.Tools.UpdateComponents,
      AgenticUi.LLM.Tools.UpdateDataModel,
      AgenticUi.LLM.Tools.DeleteSurface
    ],
    system_prompt: &AgenticUi.LLM.SystemPrompt.build/1
end
```

Per-conversation lifecycle:

```elixir
# On first channel join for a conversation_id:
{:ok, pid} = AgenticUi.Jido.start_agent(AgenticUi.LLM.Agent, id: conversation_id)
# On subsequent joins:
pid = AgenticUi.Jido.whereis(conversation_id)
```

System prompt structure:

1. Role: "You render UIs by emitting A2UI v0.9 messages targeting the MeldUI catalog."
2. Embedded catalog JSON (~35 components, fits comfortably).
3. Rules: always `createSurface` before `updateComponents`; one root component; reference children by ID; bind data with JSON Pointer; prefer `Markdown` for prose; use `Card`/`Column`/`Row` for layout.
4. Mode-specific addendum (tool-call vs streamed-JSON — see §4.5).
5. The current data model state for any live surfaces (so the model knows what's already on screen).

### 4.4 Tools as Jido.Action

Each tool's `run/2` validates the envelope, broadcasts it over PubSub to the channel topic, and returns a short `:ok` (or the schema error). The channel topic is threaded into the action via `Jido.AI.Agent.ask_stream/3`'s `tool_context:` option — Jido merges it into every action's second argument.

```elixir
defmodule AgenticUi.LLM.Tools.UpdateComponents do
  use Jido.Action,
    name: "update_components",
    description: "Append or replace components in an A2UI surface.",
    schema: Zoi.object(%{
      surface_id: Zoi.string(),
      components: Zoi.array(Zoi.map())  # flat adjacency list
    })

  @impl true
  def run(args, %{conversation_id: cid}) do
    case AgenticUi.A2UI.Validator.validate({:update_components, args}) do
      :ok ->
        Phoenix.PubSub.broadcast(
          AgenticUi.PubSub,
          "chat:" <> cid,
          {:a2ui_envelope, {:update_components, args}}
        )
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}   # fed back to the model as a tool result
    end
  end
end
```

The channel's per-turn Task calls `LLM.Agent.ask_stream(agent_pid, content, tool_context: %{conversation_id: cid})` — that's the bridge.

### 4.5 Two emission modes

Mode is per-conversation, set at creation, stored on the Conversation row.

- **`:tool_calls` mode** — system prompt instructs the model to call the four tools. Every tool call is a complete, validated envelope. This is the production path.
- **`:streamed_json` mode** — system prompt instructs the model to write A2UI envelopes as JSON in its message body, one envelope per line (JSONL). We tee the streaming text through a partial JSON line splitter, validate each complete line, and push it. Closer to the protocol's "stream of JSON" intent. Useful blog comparison; expect to discover its rough edges.

A toggle in the chat UI switches modes for the next conversation.

### 4.6 The validator (the "trust but verify" gate)

`AgenticUi.A2UI.Validator.validate(envelope)`:

1. Schema-validates against A2UI v0.9 envelope schema (vendored under `priv/a2ui/`).
2. For `updateComponents`: every `component` field must be in the MeldUI catalog; required props per component must be present; every child ID must resolve.
3. On failure in tool-call mode → return error to the model as the tool result; the loop self-corrects.
4. On failure in streamed-JSON mode → push an `error` envelope to the channel and drop the bad line; report it in the next user turn.

### 4.7 ChatChannel

Topic: `chat:<conversation_id>`. Messages:

**Inbound (from client):**
- `"user_message"` — `{content}` — appends to history, kicks off LLM run
- `"a2ui_action"` — `{surface_id, name, source_component_id, context}` — A2UI v1 client→server action; forwarded into the LLM loop as a tool result (in tool-call mode) or as a structured user turn (in streamed-JSON mode)
- `"a2ui_error"` — client-side validation/render error; logged + fed back to LLM as a system note

**Outbound (to client):**
- `"assistant_token"` — `{delta}` — streaming text tokens for the chat panel
- `"a2ui_envelope"` — one of the four envelope types
- `"assistant_done"` — `{message_id}` — turn finished
- `"error"` — `{message}` — surfaced to the user

### 4.8 Persistence

```
conversations
  id            uuid pk
  title         text
  mode          text   # "tool_calls" | "streamed_json"
  model         text   # e.g. "claude-sonnet-4-5-20250929"
  inserted_at   timestamp

messages
  id              uuid pk
  conversation_id uuid fk
  role            text   # "user" | "assistant" | "tool" | "system"
  content         text
  tool_calls      jsonb  # array of Anthropic tool_use blocks
  tool_results    jsonb  # paired tool_result blocks for the prior turn
  inserted_at     timestamp

surface_snapshots
  conversation_id uuid fk
  surface_id      text
  envelope_log    jsonb  # array of envelopes in order
  data_model      jsonb
  updated_at      timestamp
  pk (conversation_id, surface_id)
```

On reconnect: the channel pushes the full `envelope_log` for each live surface so the client re-hydrates without re-prompting the LLM.

### 4.9 Per-conversation orchestration

Jido owns the per-conversation process. `AgenticUi.Jido` (`use Jido, otp_app: :agentic_ui`) brings a `DynamicSupervisor` + `Registry` that supervise one `Jido.AgentServer` per `conversation_id`:

- **First join** for a `conversation_id` calls `AgenticUi.Jido.start_agent(AgenticUi.LLM.Agent, id: conversation_id)`; subsequent joins call `AgenticUi.Jido.whereis(conversation_id)`.
- **Conversation history** lives on `agent.state[:__thread__]` (a `Jido.Thread` maintained by the ReAct strategy) while the AgentServer is alive. We mirror each completed turn into `messages` rows so the conversation survives an AgentServer crash or app restart.
- **User turn flow**: the channel's per-turn `Task` calls `AgenticUi.LLM.Agent.ask_stream/3`, iterates the events enumerable (`Jido.Signal` structs with types `ai.llm.delta`, `ai.tool.started`, `ai.tool.result`, `ai.llm.response`, `ai.usage`), relays the deltas + envelopes to the client via direct `send/2` to the channel pid (or `Phoenix.PubSub` once tools start broadcasting), and writes the user + assistant rows at the boundaries.
- **Re-hydration on cold start** (Phase 1): when the AgentServer dies/restarts but DB rows remain, the first user turn seeds the agent's context from DB via `Jido.AI.Context.append_messages/2` before continuing.

## 5. Frontend design

### 5.1 Dependencies to add (`frontend/package.json`)

```
@meldui/a2ui         # catalog + types
@a2ui/web_core       # reference renderer (web components)
```

### 5.2 File layout

```
frontend/src/
├── views/
│   ├── HomeView.vue              conversation list + "new chat" CTA
│   └── ChatView.vue              the chat screen for one conversation
├── components/
│   ├── ChatMessageList.vue
│   ├── ChatComposer.vue
│   ├── A2UISurface.vue           thin Vue wrapper around @a2ui/web_core
│   ├── EnvelopeInspector.vue     "view raw A2UI" toggle, JSON pretty-print
│   └── ModeToggle.vue            tool_calls ↔ streamed_json
├── stores/
│   ├── conversations.ts          Pinia: list, create
│   └── chat.ts                   Pinia: messages + surfaces for active conv
├── composables/
│   └── useChatChannel.ts         wraps phoenix.Socket + Channel for one conv
└── lib/
    ├── a2ui-bridge.ts            wires @a2ui/web_core events ↔ Phoenix Channel
    └── api.ts                    REST: GET/POST /api/conversations
```

### 5.3 The A2UI renderer wrapper

`@a2ui/web_core` exposes a web component that takes the envelope stream as input and emits action events. The Vue wrapper:

- Subscribes to `a2ui_envelope` channel events; for envelopes matching this surface's `surface_id`, forwards them into the web component.
- Listens for the web component's `action` event; pushes it back over the channel as `a2ui_action`.
- Listens for client-side errors; pushes them as `a2ui_error`.

On mount with an existing conversation, the wrapper replays `envelope_log` from the store before subscribing to live events — gives us perfect re-hydration.

### 5.4 Routing

```ts
// frontend/src/router/index.ts
{ path: '/', component: HomeView },
{ path: '/c/:id', component: ChatView, props: true },
{ path: '/:catchAll(.*)', component: NotFoundView }
```

The Phoenix catch-all already in `router.ex` handles deep-link refreshes.

## 6. End-to-end walkthrough

User opens `/c/<id>`. Vue mounts `ChatView`, opens Channel `chat:<id>`. Channel join replays the envelope log → the surfaces re-render exactly as they were. The chat history loads from the conversations API.

User types "show me a dashboard for our Q3 sales". Channel push `user_message`.

Conversation GenServer appends the message, kicks off the Jido agent stream. As tokens arrive:
- Assistant text → `assistant_token` events → chat panel.
- Claude calls `create_surface` → tool runs → envelope validated → `a2ui_envelope` pushed → `<A2UISurface>` web component creates the surface.
- Claude calls `update_components` (maybe several times as it builds the tree) → each pushed → web component patches its tree.
- Claude calls `update_data_model` with the actual numbers → web component re-renders bound nodes.

Stream ends → `assistant_done`.

User clicks a button rendered inside the surface. Web component fires `action` → bridge pushes `a2ui_action` with the bound data-model context → GenServer feeds it into the LLM (as a tool result if we faked the action as a tool, or as a user turn) → Claude reacts, perhaps calling `update_data_model` to drill into a row. Loop continues.

## 7. Implementation phases

Each phase ends with something demonstrable.

**Phase 0 — Plumbing.** Add deps, configure `ANTHROPIC_API_KEY`, create Conversation/Message/SurfaceSnapshot schemas + migrations, UserSocket + ChatChannel skeleton, Conversation GenServer skeleton. Smoke test: open a channel, echo messages.

**Phase 1 — Plain chat over the channel.** Wire Jido agent to Claude (no A2UI yet, no tools yet). Stream assistant tokens. Frontend `ChatView` with message list + composer. Persistence working. Demo: have a normal text conversation.

**Phase 2 — Catalog loading + system prompt.** Fetch the MeldUI catalog at boot (cache in ETS), build the system prompt with it embedded. Add the four Jido.Action tools but have them just log + ack. Confirm Claude calls them sensibly.

**Phase 3 — A2UI rendering, tool-call mode.** Wire the tools to actually broadcast envelopes. Frontend: `<A2UISurface>` wrapper around `@a2ui/web_core`. Validator in front of the broadcast. Demo: "render a card with my name" → card appears.

**Phase 4 — Action round-trip.** Client → `a2ui_action` → GenServer → Claude → reaction. Demo: form with a submit button that the model reacts to.

**Phase 5 — Streamed-JSON mode.** Second emission mode behind the toggle. JSONL line splitter on the assistant stream. Same validator. Demo: comparison page showing the same prompt rendered both ways.

**Phase 6 — Polish for the blog.** Conversations list, envelope inspector toggle, scenario presets ("Dashboard", "Form", "Markdown report", "Chart"), token/latency display. Screenshots, a GIF or two.

## 8. Unknowns to resolve in flight

- **jido_ai streaming event shape.** The hexdocs will tell us; expect to wrap whatever `Jido.AI.stream_text/2` (or the agent's streaming entry point) emits into a clean per-token / per-tool-call stream we can fan out. May require reading `req_llm` source — log findings in `NOTES.md` as you go (good blog input).
- **Tool-call streaming granularity.** Anthropic streams tool calls token-by-token but they only become valid JSON at the end of the block. Confirm `req_llm` already buffers tool-call deltas into complete calls; if not, buffer ourselves before passing to the Jido action.
- **`@a2ui/web_core` Vue ergonomics.** It's a web component, so two-way Vue binding works but events come through DOM custom events. The wrapper should normalize this. Verify the package exports during Phase 3.
- **Catalog component coverage in `@a2ui/web_core`.** The reference renderer may not yet implement every MeldUI-specific component. Test the rich tier (Markdown, Chart, Timeline) early; fall back to a simple Vue renderer for any gaps before Phase 6.
- **Streamed-JSON mode robustness.** Claude may not strictly emit one envelope per line. Be ready to use a tolerant partial-JSON parser if the line-based approach is too brittle.

## 9. Blog narrative beats

Stuff worth highlighting as you implement, for the eventual post:

1. **Why A2UI vs. "just have the LLM emit React/Vue"** — the catalog-as-contract pattern, the safety argument (no code execution), the cross-framework angle.
2. **Tool calls vs. streamed JSON** — same problem, two solutions; show the code diff, show the trade-offs (latency, validation, progressive rendering quality).
3. **The validator as a co-pilot for the LLM** — schema failures fed back as tool errors close the gap between "JSON soup" and "valid UI."
4. **The bidirectional loop** — most LLM demos are one-shot; A2UI flips chat into something that looks like an agent driving an app.
5. **Why Phoenix Channels fit perfectly** — bidirectional, ordered, gracefully reconnect with re-hydration from the surface log.
6. **Jido as the agent runtime** — what it gave us, what we didn't need.

## 10. Acceptance criteria for "POC done"

- [ ] Can chat with Claude in a Vue SPA over a Phoenix Channel.
- [ ] A prompt like "build me a sales dashboard with these three KPIs" produces a rendered MeldUI surface inside the chat panel.
- [ ] A button inside that surface triggers a follow-up LLM turn that mutates the surface (e.g. drill-in).
- [ ] Reload preserves the conversation and the rendered surfaces.
- [ ] Toggle between tool-call and streamed-JSON modes works for the same prompt.
- [ ] Schema-invalid envelopes are caught before reaching the client; the LLM recovers from them in tool-call mode.
- [ ] At least one scenario for each catalog tier (basic / structural / rich) renders correctly.
