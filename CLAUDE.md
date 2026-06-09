# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`AgenticUi` is a Phoenix application. Stack: **Phoenix 1.8 + Vue 3 + Postgres + Oban**.

- OTP app: `:agentic_ui`
- Module namespaces: `AgenticUi.*` (business logic — Repo, Mailer, Application) and `AgenticUiWeb.*` (web layer — Endpoint, Router, etc.)
- Dev DB: `agentic_ui_dev` (Postgres, default `postgres`/`postgres` from `config/dev.exs`)

## Essential commands

All from `mix.exs` aliases:

```
mix setup                              # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server                         # dev server on :4000 with live reload + watchers
iex -S mix phx.server                  # same, with IEx shell attached
mix test                               # auto-creates test DB, runs ExUnit
mix test test/path/to/file_test.exs:42 # single test by file + line
mix test --failed                      # rerun last failures
mix ecto.reset                         # drop + create + migrate + seed
mix assets.build                       # pnpm vite build
mix assets.deploy                      # vite build --mode production + phx.digest
mix credo --strict                     # static analysis (.credo.exs)
mix dialyzer                           # type analysis (PLT cached in priv/plts/)
mix precommit                          # compile --warnings-as-errors + deps.unlock --unused + format + credo --strict + dialyzer + test
```

Run `mix precommit` before every commit.

<!-- phoenix_vue:gen.auth:claude_anchor:begin -->
## Authentication

**Not yet enabled.** This project ships with a single-shot generator that lands a complete auth stack — User / PasswordCredential / Session / Organization / Member schemas, JSON API, Vue SPA pages (sign-up / login / forgot-password / email verification / onboarding), Pinia auth store, CSRF-aware fetch wrapper.

```sh
mix phoenix_vue.gen.auth --mode multi    # users can belong to N organizations (default)
mix phoenix_vue.gen.auth --mode single   # one organization per user, auto-created at signup
mix deps.get && mix ecto.migrate
```

The generator is single-shot and refuses to re-run. When it lands, it replaces this section with the post-install description (which modules went where, what's wired vs not, mode chosen).
<!-- phoenix_vue:gen.auth:claude_anchor:end -->

## Architecture

- `lib/agentic_ui/` — business logic root: `application.ex`, `repo.ex`, `mailer.ex`. New contexts go here.
- `lib/agentic_ui_web/` — web layer: `endpoint.ex`, `router.ex`, `telemetry.ex`, `components/`, `controllers/`, `gettext.ex`, `plugs/`. `PageController.home` renders the SPA shell; a catch-all `GET /*path` at the bottom of `router.ex` sends every browser path through it so vue-router survives deep-link refreshes.
- `frontend/` — Vue 3 SPA bundled by Vite 8 (Tailwind v4 + Meldui + Pinia + Vue Router 5, OXC toolchain). Full layout + conventions in the [**Frontend (Vue 3 SPA)**](#frontend-vue-3-spa) section below. `phoenix` npm + `@types/phoenix` are pre-installed so Channels are one UserSocket + endpoint route away when needed.
- `priv/static/assets/` — Vite build output (gitignored). Populated by `mix assets.build` / `mix assets.deploy`. **No `assets/` directory** on the Phoenix side — Vite owns all CSS/JS.
- `priv/repo/migrations/` — Ecto migrations (Oban schema landed in the initial `add_oban` migration).
- HTTP server: Bandit (`Bandit.PhoenixAdapter` in `config/config.exs`).

## Frontend (Vue 3 SPA)

### Layout

```
frontend/
├── index.html               SPA shell — <title> + <div id="app">
├── package.json             pnpm; engines node ^20.19 || >=22.12
├── pnpm-lock.yaml
├── env.d.ts                 /// <reference types="vite/client" />
├── vite.config.ts           dev :4001, HMR :4002, outDir → ../priv/static
├── vite-dev.mjs             dev wrapper that exits when Phoenix closes stdin
├── tsconfig.json            workspace references → app + node
├── tsconfig.app.json        DOM + Vue, paths { "@/*": ["./src/*"] }
├── tsconfig.node.json       vite.config / eslint.config type-checking
├── eslint.config.ts         flat config; vue-essential + oxlint
├── .oxlintrc.json / .oxfmtrc.json
├── .editorconfig / .gitattributes / .gitignore
└── src/
    ├── main.ts              createApp + pinia + router; mounts #app
    ├── App.vue              <RouterView /> + <Toaster /> (meldui)
    ├── assets/
    │   └── main.css         tailwindcss + tw-animate-css + meldui theme
    │                        + Geist/Bricolage fonts + Tailwind @source paths
    ├── router/
    │   └── index.ts         createWebHistory; home + 404 catch-all
    ├── views/               page components mapped from the router
    │   ├── HomeView.vue
    │   └── NotFoundView.vue
    └── lib/                 framework-agnostic helpers
        └── csrf.ts          read <meta name="csrf-token">
```

### Where new code goes

- `src/views/` — top-level page components mapped from `src/router/index.ts`. One file per route, PascalCase, suffix `View.vue`.
- `src/components/` — reusable UI not bound to a route. Create when the same fragment renders in ≥ 2 views.
- `src/composables/` — Vue composition functions (`useFoo`); one concern per file, export a single `use*`.
- `src/stores/` — Pinia stores (`defineStore`). State that outlives a single view (auth, current org, etc.).
- `src/lib/` — framework-agnostic TS helpers (CSRF, API client, formatters, time, hash).
- `src/types/` — shared TS types / Zod schemas.
- `src/assets/` — global CSS only. Per-component CSS belongs in the `.vue` `<style>` block.
- Use the `@` alias for cross-directory imports: `import { getCsrfToken } from '@/lib/csrf'`.

### Commands (from `frontend/`)

```
pnpm dev          # standalone vite — rarely needed; mix phx.server runs it
pnpm build        # type-check + production bundle into ../priv/static
pnpm preview      # serve the production bundle locally
pnpm type-check   # vue-tsc --build (incremental; cached in node_modules/.tmp)
pnpm lint         # oxlint --fix → eslint --fix --cache
pnpm format       # oxfmt src/
```

### HMR flow

`mix phx.server` spawns `node vite-dev.mjs` via the Phoenix watcher in `config/dev.exs`. Vite serves modules from `:4001`; `root.html.heex` injects `<script src="//{request_host}:4001/src/main.ts">` so the browser pulls everything live. Edits to `.vue`, `.ts`, or `.css` files HMR without a full reload. `.heex` / router changes still trigger a Phoenix `live_reload`.

## Background jobs (Oban)

Oban runs in a two-release topology — queues split by `RELEASE_NAME` in `config/runtime.exs`:

- `agentic_ui_server` (web) — `default` + `mailer` queues; hosts Pruner + Cron plugins.
- `agentic_ui_processors` — heavy queues you add as features land (e.g. `documents`, `embeddings`); Pruner only.
- Dev / iex / test (no `RELEASE_NAME`) — all queues run on one node.

Workers go under `lib/agentic_ui/.../workers/`. Pattern:

```elixir
defmodule AgenticUi.Some.Workers.MyWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: :ok
end
```

Tests use `config :agentic_ui, Oban, testing: :inline` (jobs run synchronously on enqueue).

## Dev flow

`mix phx.server` runs Phoenix on `:4000` and spawns Vite on `:4001`. The root layout (`lib/agentic_ui_web/components/layouts/root.html.heex`) conditionally injects either the dev `<script src="//host:4001/@vite/client">` tags or the prod digested `/assets/main.{js,css}` links, keyed off `Application.get_env(:agentic_ui, :vite_dev_server)`. Prod build: `MIX_ENV=prod mix assets.deploy` → Vite builds + `phx.digest` cache-busts.

## Framework rules — see AGENTS.md

`AGENTS.md` is the source of truth for Phoenix 1.8 / LiveView / Ecto / HEEx / Elixir / forms / streams / test conventions. **Read it before writing code.** High-level reminders that come up constantly:

- **HTTP client is `Req` only** — never HTTPoison / Tesla / httpc.
- **Tailwind v4 lives on the Vue side** — `frontend/src/assets/main.css` is canonical (no `tailwind.config.js`, no Phoenix-side asset pipeline).
- **Use Meldui for SPA UI** — `import { Button, ... } from '@meldui/vue'` and `@meldui/tabler-vue` for icons. Don't reintroduce daisyUI.
- **Forms always via `Phoenix.Component.to_form/2`**; never pass a changeset directly to `<.form for=...>`.
- **No `live_redirect` / `live_patch`** — use `<.link navigate>` / `push_navigate`.
- **No `String.to_atom/1` on user input** (memory leak).
- **No `Phoenix.View`** (removed).

## Commit message conventions

- **Never add `Co-Authored-By: Claude ...` trailers** to commit messages. Author the commit normally; no AI attribution.
