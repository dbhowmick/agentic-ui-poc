import { getCsrfToken } from '@/lib/csrf'
import type { Conversation, ConversationMode } from '@/types/chat'

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set('accept', 'application/json')
  if (init.body !== undefined) headers.set('content-type', 'application/json')
  const csrf = getCsrfToken()
  if (csrf) headers.set('x-csrf-token', csrf)

  const res = await fetch(path, { ...init, headers, credentials: 'same-origin' })
  if (!res.ok) {
    const detail = await res.text().catch(() => '')
    throw new Error(`${res.status} ${res.statusText}${detail ? `: ${detail}` : ''}`)
  }
  return (await res.json()) as T
}

export async function listConversations(): Promise<Conversation[]> {
  const { conversations } = await request<{ conversations: Conversation[] }>(
    '/api/conversations',
  )
  return conversations
}

export interface CreateConversationInput {
  mode?: ConversationMode
  model?: string
  title?: string | null
}

export async function createConversation(
  input: CreateConversationInput = {},
): Promise<Conversation> {
  const { conversation } = await request<{ conversation: Conversation }>(
    '/api/conversations',
    { method: 'POST', body: JSON.stringify(input) },
  )
  return conversation
}

export async function getConversation(id: string): Promise<Conversation> {
  const { conversation } = await request<{ conversation: Conversation }>(
    `/api/conversations/${id}`,
  )
  return conversation
}
