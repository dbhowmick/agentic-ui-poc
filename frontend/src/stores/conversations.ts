import { defineStore } from 'pinia'
import { ref } from 'vue'
import * as api from '@/lib/api'
import type { Conversation, ConversationMode } from '@/types/chat'

export const useConversationsStore = defineStore('conversations', () => {
  const list = ref<Conversation[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function fetchAll() {
    loading.value = true
    error.value = null
    try {
      list.value = await api.listConversations()
    } catch (e) {
      error.value = e instanceof Error ? e.message : String(e)
    } finally {
      loading.value = false
    }
  }

  async function create(input: {
    mode?: ConversationMode
    model?: string
    title?: string | null
  } = {}): Promise<Conversation> {
    const conv = await api.createConversation(input)
    list.value = [conv, ...list.value]
    return conv
  }

  return { list, loading, error, fetchAll, create }
})
