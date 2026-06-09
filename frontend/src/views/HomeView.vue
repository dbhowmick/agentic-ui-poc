<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { Button, toast } from '@meldui/vue'
import { IconMessageCircle, IconPlus } from '@meldui/tabler-vue'
import { useConversationsStore } from '@/stores/conversations'
import type { Conversation } from '@/types/chat'

const router = useRouter()
const conversations = useConversationsStore()

const rows = computed(() => conversations.list ?? [])

onMounted(() => {
  conversations.fetchAll()
})

async function newChat() {
  try {
    const conv = await conversations.create({ mode: 'tool_calls' })
    router.push({ name: 'chat', params: { id: conv.id } })
  } catch (e) {
    toast.error(e instanceof Error ? e.message : String(e))
  }
}

function label(c: Conversation) {
  if (c.title && c.title.trim() !== '') return c.title
  return `Untitled · ${c.id.slice(0, 8)}`
}

function timeAgo(iso: string) {
  const then = new Date(iso).getTime()
  const now = Date.now()
  const sec = Math.max(1, Math.round((now - then) / 1000))
  if (sec < 60) return `${sec}s ago`
  const min = Math.round(sec / 60)
  if (min < 60) return `${min}m ago`
  const hr = Math.round(min / 60)
  if (hr < 24) return `${hr}h ago`
  const day = Math.round(hr / 24)
  return `${day}d ago`
}
</script>

<template>
  <main class="min-h-screen bg-background">
    <div class="mx-auto max-w-2xl px-6 py-12">
      <header class="mb-10 flex items-center justify-between">
        <div>
          <h1 class="font-display text-3xl font-semibold tracking-tight">AgenticUi</h1>
          <p class="mt-1 text-sm text-muted-foreground">A2UI POC — chat with Claude.</p>
        </div>
        <Button @click="newChat">
          <IconPlus class="size-4" />
          New chat
        </Button>
      </header>

      <div v-if="conversations.loading" class="text-sm text-muted-foreground">
        Loading…
      </div>

      <div
        v-else-if="rows.length === 0"
        class="rounded-xl border border-dashed py-16 text-center"
      >
        <IconMessageCircle class="mx-auto size-8 text-muted-foreground" />
        <p class="mt-4 text-sm text-muted-foreground">No conversations yet.</p>
        <Button class="mt-4" @click="newChat">
          <IconPlus class="size-4" />
          Start chatting
        </Button>
      </div>

      <ul v-else class="flex flex-col gap-2">
        <li v-for="c in rows" :key="c.id">
          <RouterLink
            :to="{ name: 'chat', params: { id: c.id } }"
            class="flex items-center justify-between rounded-lg border bg-card px-4 py-3 transition-colors hover:bg-muted/50"
          >
            <div class="flex flex-col">
              <span class="text-sm font-medium">{{ label(c) }}</span>
              <span class="text-xs text-muted-foreground">{{ timeAgo(c.inserted_at) }}</span>
            </div>
            <span
              class="rounded-full bg-muted px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-muted-foreground"
            >{{ c.mode }}</span>
          </RouterLink>
        </li>
      </ul>
    </div>
  </main>
</template>
