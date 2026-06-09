<script setup lang="ts">
import { watch } from 'vue'
import { RouterLink } from 'vue-router'
import { toast } from '@meldui/vue'
import { IconArrowLeft } from '@meldui/tabler-vue'
import ChatMessageList from '@/components/ChatMessageList.vue'
import ChatComposer from '@/components/ChatComposer.vue'
import { useChatChannel } from '@/composables/useChatChannel'

const props = defineProps<{ id: string }>()

const { messages, streaming, error, send } = useChatChannel(props.id)

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
