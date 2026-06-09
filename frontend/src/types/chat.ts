export type ConversationMode = 'tool_calls' | 'streamed_json'

export interface Conversation {
  id: string
  title: string | null
  mode: ConversationMode
  model: string
  inserted_at: string
  updated_at: string
}

export type MessageRole = 'user' | 'assistant' | 'tool' | 'system'

export interface Message {
  id: string
  conversation_id: string
  role: MessageRole
  content: string | null
  tool_calls: unknown[]
  tool_results: unknown[]
  surface_ids?: string[]
  inserted_at: string
}

// A2UI v0.9 wire envelope as emitted by the backend tools and consumed by
// @meldui/a2ui/vue's processor.processMessages. The four shapes are mutually
// exclusive; we only inspect well-known top-level keys here, full schemas live
// in @a2ui/web_core.
export interface A2UIEnvelope {
  version: 'v0.9'
  createSurface?: { surfaceId: string; catalogId: string; theme?: unknown; sendDataModel?: boolean }
  updateComponents?: { surfaceId: string; components: Array<Record<string, unknown>> }
  updateDataModel?: { surfaceId: string; path?: string; value?: unknown }
  deleteSurface?: { surfaceId: string }
}

export interface SurfaceReplay {
  surface_id: string
  envelope_log: A2UIEnvelope[]
  data_model: Record<string, unknown>
  updated_at: string
}

// A2UI v0.9 client→server action — emitted by @a2ui/web_core when a user
// triggers a component's `action.event` (button click, form submit, etc.).
// Mirrors the zod schema in @a2ui/web_core/v0_9/schema/client-to-server.js.
export interface A2uiClientAction {
  name: string
  surfaceId: string
  sourceComponentId: string
  timestamp: string
  context: Record<string, unknown>
}
