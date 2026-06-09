import { onBeforeUnmount, ref, shallowRef } from 'vue'
import type { Channel } from 'phoenix'
import { getSocket } from '@/lib/socket'
import type { Message } from '@/types/chat'

interface HistoryPayload {
  messages: Message[]
}

interface TokenPayload {
  delta: string
}

interface ErrorPayload {
  message: string
}

export interface UseChatChannel {
  messages: ReturnType<typeof ref<Message[]>>
  streaming: ReturnType<typeof ref<boolean>>
  ready: ReturnType<typeof ref<boolean>>
  error: ReturnType<typeof ref<string | null>>
  send: (content: string) => void
}

function tempId(prefix: string) {
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}`
}

export function useChatChannel(conversationId: string): UseChatChannel {
  const messages = ref<Message[]>([])
  const streaming = ref(false)
  const ready = ref(false)
  const error = ref<string | null>(null)
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

  channel.on('assistant_done', () => {
    streaming.value = false
    streamingId.value = null
  })

  channel.on('error', ({ message }: ErrorPayload) => {
    error.value = message
    streaming.value = false
    streamingId.value = null
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

  onBeforeUnmount(() => {
    channelRef.value?.leave()
    channelRef.value = null
  })

  return { messages, streaming, ready, error, send }
}
