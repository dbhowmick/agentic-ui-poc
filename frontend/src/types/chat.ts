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
  inserted_at: string
}
