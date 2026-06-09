<script setup lang="ts">
import { watch } from 'vue'
import { RouterLink } from 'vue-router'
import { toast } from '@meldui/vue'
import { IconArrowLeft } from '@meldui/tabler-vue'
import { provideA2UI } from '@meldui/a2ui/vue'
import ChatMessageList from '@/components/ChatMessageList.vue'
import ChatComposer from '@/components/ChatComposer.vue'
import { useChatChannel } from '@/composables/useChatChannel'
import type { A2UIEnvelope, A2uiClientAction } from '@/types/chat'

const props = defineProps<{ id: string }>()

const { messages, streaming, error, envelopes, send, sendAction } = useChatChannel(props.id)

// One `MessageProcessor` for the whole conversation — it holds every surface
// the LLM creates. Each `<A2UISurface :surface-id="X">` mounted inside the
// message list injects this processor and subscribes to surface lifecycle
// events for its own id. The renderer handles updates idiomatically:
// `updateDataModel` patches re-evaluate `DataBinding`-typed props via
// `GenericBinder`'s signal subscriptions; the system prompt steers the LLM
// to use bindings + `update_data_model` for any value that may change.
const { processor } = provideA2UI({
  onAction: (action) => sendAction(action as A2uiClientAction),
})

// Dispatch every envelope to the processor exactly once. Object identity in a
// `WeakSet` is the dedup key — both the live `a2ui_envelope` push and the
// `a2ui_replay` array refill produce fresh deserialised objects, so each
// envelope reference is fed in at most once. Survives watcher re-fires and
// replay-then-live ordering without a fragile length cursor.
const processed = new WeakSet<object>()
watch(
  envelopes,
  (envs) => {
    if (!envs) return
    const pending: A2UIEnvelope[] = []
    for (const env of envs) {
      if (processed.has(env)) continue
      processed.add(env)
      pending.push(env)
    }
    if (pending.length > 0) {
      processor.processMessages(pending as Parameters<typeof processor.processMessages>[0])
    }
  },
  { immediate: true },
)

watch(error, (msg) => {
  if (msg) toast.error(msg)
})

function shortId(id: string) {
  return id.slice(0, 8)
}
</script>

<template>
  <main class="flex h-screen flex-col bg-background">
    <header class="flex items-center gap-3 border-b px-6 py-3">
      <RouterLink
        to="/"
        class="inline-flex size-8 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground"
        aria-label="Back to home"
      >
        <IconArrowLeft class="size-4" />
      </RouterLink>
      <div class="flex flex-col">
        <span class="text-sm font-medium">Conversation</span>
        <span class="font-mono text-xs text-muted-foreground">{{ shortId(props.id) }}</span>
      </div>
    </header>

    <ChatMessageList :messages="messages ?? []" :streaming="streaming ?? false" />

    <ChatComposer :disabled="streaming ?? false" @submit="send" />
  </main>
</template>
