import { onBeforeUnmount, ref, shallowRef } from 'vue'
import type { Channel } from 'phoenix'
import { getSocket } from '@/lib/socket'
import type {
  A2UIEnvelope,
  A2uiClientAction,
  Message,
  SurfaceReplay,
  UsageStats,
} from '@/types/chat'

interface HistoryPayload {
  messages: Message[]
}

interface TokenPayload {
  delta: string
}

interface ErrorPayload {
  message: string
}

interface ReplayPayload {
  surfaces: SurfaceReplay[]
}

interface AssistantDonePayload {
  message_id?: string
  usage?: UsageStats
  latency_ms?: number
}

export interface UseChatChannel {
  messages: ReturnType<typeof ref<Message[]>>
  streaming: ReturnType<typeof ref<boolean>>
  ready: ReturnType<typeof ref<boolean>>
  error: ReturnType<typeof ref<string | null>>
  envelopes: ReturnType<typeof ref<A2UIEnvelope[]>>
  send: (content: string) => void
  sendAction: (action: A2uiClientAction) => void
}

function tempId(prefix: string) {
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}`
}

export function useChatChannel(conversationId: string): UseChatChannel {
  const messages = ref<Message[]>([])
  const streaming = ref(false)
  const ready = ref(false)
  const error = ref<string | null>(null)
  const envelopes = ref<A2UIEnvelope[]>([])
  const channelRef = shallowRef<Channel | null>(null)
  const streamingId = ref<string | null>(null)

  const channel = getSocket().channel(`chat:${conversationId}`)
  channelRef.value = channel

  channel.on('history', ({ messages: rows }: HistoryPayload) => {
    messages.value = rows
  })

  channel.on('assistant_token', ({ delta }: TokenPayload) => {
    appendDelta(delta)
  })

  channel.on('assistant_done', (payload: AssistantDonePayload = {}) => {
    stampStreamingMessage(payload)
    streaming.value = false
    streamingId.value = null
  })

  channel.on('error', ({ message }: ErrorPayload) => {
    error.value = message
    streaming.value = false
    streamingId.value = null
  })

  channel.on('a2ui_replay', ({ surfaces }: ReplayPayload) => {
    // Flatten persisted envelope logs across all surfaces in arrival order.
    // Per-surface ordering inside each log is preserved; cross-surface ordering
    // falls back to updated_at — Phase 3 only exercises a single surface.
    const sorted = [...surfaces].sort((a, b) => a.updated_at.localeCompare(b.updated_at))
    envelopes.value = sorted.flatMap((s) => s.envelope_log)
  })

  channel.on('a2ui_envelope', (envelope: A2UIEnvelope) => {
    envelopes.value = [...envelopes.value, envelope]
    // Progressive rendering: attach the touched surfaceId to the currently
    // streaming assistant placeholder for ANY mutating envelope, not only
    // `createSurface`. The render-time owner-derivation in ChatMessageList
    // then pins each surface to the *latest* assistant turn that touched it,
    // so a resubmitted form follows the conversation downward instead of
    // staying at its original (now scrolled-up) position. `deleteSurface` is
    // skipped — the processor's onSurfaceDeleted signal removes the renderer
    // and there's no useful "owner" for a destroyed surface. If no
    // placeholder exists yet (a tool fired before the first text delta) the
    // attach helper creates one with empty content; the persisted row at
    // `assistant_done` will replace the placeholder and carry the canonical
    // touched-surface list from the backend.
    const sid = touchedSurfaceId(envelope)
    if (sid) attachSurfaceIdToStreamingMessage(sid)
  })

  channel
    .join()
    .receive('ok', () => {
      ready.value = true
    })
    .receive('error', ({ reason }: { reason?: string }) => {
      error.value = reason ?? 'channel_join_failed'
    })
    .receive('timeout', () => {
      error.value = 'channel_join_timeout'
    })

  // On `assistant_done` the backend hands back the persisted row id alongside
  // the per-turn usage rollup and wall-clock latency. Stamp them onto the
  // optimistic streaming placeholder so the footer renders without waiting
  // for a history refetch. On a stale reconnect (no streamingId) this is a
  // no-op — the next channel `history` push carries authoritative values.
  function stampStreamingMessage(payload: AssistantDonePayload) {
    const list = messages.value ?? []
    const id = streamingId.value
    const idx = id ? list.findIndex((m) => m.id === id) : -1
    const target = idx >= 0 ? list[idx] : undefined
    if (!target) return
    const next: Message = {
      ...target,
      id: payload.message_id ?? target.id,
      usage: payload.usage ?? target.usage,
      latency_ms: payload.latency_ms ?? target.latency_ms,
    }
    messages.value = [...list.slice(0, idx), next, ...list.slice(idx + 1)]
  }

  function touchedSurfaceId(envelope: A2UIEnvelope): string | null {
    return (
      envelope.createSurface?.surfaceId ??
      envelope.updateComponents?.surfaceId ??
      envelope.updateDataModel?.surfaceId ??
      null
    )
  }

  function attachSurfaceIdToStreamingMessage(surfaceId: string) {
    const list = messages.value ?? []
    const id = streamingId.value
    const idx = id ? list.findIndex((m) => m.id === id) : -1
    const target = idx >= 0 ? list[idx] : undefined

    if (!target) {
      // No streaming message yet — spawn an empty placeholder so the panel
      // has a host to sit under.
      const newId = tempId('asst')
      streamingId.value = newId
      const placeholder: Message = {
        id: newId,
        conversation_id: conversationId,
        role: 'assistant',
        content: '',
        tool_calls: [],
        tool_results: [],
        surface_ids: [surfaceId],
        inserted_at: new Date().toISOString(),
      }
      messages.value = [...list, placeholder]
      return
    }

    const existing = target.surface_ids ?? []
    if (existing.includes(surfaceId)) return
    const next: Message = { ...target, surface_ids: [...existing, surfaceId] }
    messages.value = [...list.slice(0, idx), next, ...list.slice(idx + 1)]
  }

  function appendDelta(delta: string) {
    const list = messages.value ?? []
    const id = streamingId.value
    const idx = id ? list.findIndex((m) => m.id === id) : -1
    const target = idx >= 0 ? list[idx] : undefined
    if (target) {
      const next: Message = { ...target, content: (target.content ?? '') + delta }
      messages.value = [...list.slice(0, idx), next, ...list.slice(idx + 1)]
    } else {
      const newId = tempId('asst')
      streamingId.value = newId
      const placeholder: Message = {
        id: newId,
        conversation_id: conversationId,
        role: 'assistant',
        content: delta,
        tool_calls: [],
        tool_results: [],
        inserted_at: new Date().toISOString(),
      }
      messages.value = [...list, placeholder]
    }
  }

  function send(content: string) {
    const trimmed = content.trim()
    if (!trimmed || streaming.value) return
    error.value = null
    const optimisticUser: Message = {
      id: tempId('user'),
      conversation_id: conversationId,
      role: 'user',
      content: trimmed,
      tool_calls: [],
      tool_results: [],
      inserted_at: new Date().toISOString(),
    }
    messages.value = [...(messages.value ?? []), optimisticUser]
    streaming.value = true
    streamingId.value = null
    channel.push('user_message', { content: trimmed }).receive('error', (err) => {
      streaming.value = false
      streamingId.value = null
      error.value = typeof err === 'string' ? err : 'send_failed'
    })
  }

  function sendAction(action: A2uiClientAction) {
    // Drop actions issued while a turn is in flight — the LLM is already
    // working on something for this conversation and accepting another
    // user-side turn mid-stream would let the model race itself.
    if (streaming.value) {
      error.value = 'Please wait for the current reply before interacting again.'
      return
    }
    error.value = null
    // Mirror `send/1`'s optimistic-bubble pattern with an action chip. The
    // backend persists this same shape (role=user, content prefixed by
    // `[a2ui_action]`, action payload at tool_results[0]) so refresh from
    // history will produce an identical-looking row.
    const optimisticAction: Message = {
      id: tempId('action'),
      conversation_id: conversationId,
      role: 'user',
      content: `[a2ui_action] surface=${action.surfaceId} source=${action.sourceComponentId} name=${action.name}`,
      tool_calls: [],
      tool_results: [action as unknown as Record<string, unknown>],
      inserted_at: new Date().toISOString(),
    }
    messages.value = [...(messages.value ?? []), optimisticAction]
    streaming.value = true
    streamingId.value = null
    channel.push('a2ui_action', action as unknown as object).receive('error', (err) => {
      streaming.value = false
      streamingId.value = null
      error.value = typeof err === 'string' ? err : 'action_failed'
    })
  }

  onBeforeUnmount(() => {
    channelRef.value?.leave()
    channelRef.value = null
  })

  return { messages, streaming, ready, error, envelopes, send, sendAction }
}
