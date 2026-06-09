<script setup lang="ts">
import { computed, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { toast } from '@meldui/vue'
import { IconArrowLeft } from '@meldui/tabler-vue'
import ChatMessageList from '@/components/ChatMessageList.vue'
import ChatComposer from '@/components/ChatComposer.vue'
import A2UISurfacePanel from '@/components/A2UISurfacePanel.vue'
import { useChatChannel } from '@/composables/useChatChannel'
import type { A2UIEnvelope } from '@/types/chat'

const props = defineProps<{ id: string }>()

const { messages, streaming, error, envelopes, send, sendAction } = useChatChannel(props.id)

watch(error, (msg) => {
  if (msg) toast.error(msg)
})

// Bumped on every envelope log change so `<A2UISurfacePanel>` remounts with a
// fresh `MessageProcessor` and replays the full log. See A2UISurfacePanel.vue
// for the upstream bugs this works around.
const surfacePanelKey = computed(() => envelopes.value?.length ?? 0)

const envelopeLog = computed<A2UIEnvelope[]>(() => envelopes.value ?? [])

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

    <div class="flex min-h-0 flex-1">
      <div class="flex flex-1 flex-col">
        <ChatMessageList :messages="messages ?? []" :streaming="streaming ?? false" />
        <ChatComposer :disabled="streaming ?? false" @submit="send" />
      </div>
      <aside class="hidden w-[420px] flex-col border-l bg-card lg:flex">
        <div class="border-b px-4 py-3 text-sm font-medium">Surface</div>
        <div class="flex-1 overflow-auto p-4">
          <A2UISurfacePanel
            :key="surfacePanelKey"
            :envelopes="envelopeLog"
            surface-id="main"
            :on-action="sendAction"
          />
        </div>
      </aside>
    </div>
  </main>
</template>
