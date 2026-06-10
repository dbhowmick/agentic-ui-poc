<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { Button, toast } from '@meldui/vue'
import { IconArrowLeft, IconCode } from '@meldui/tabler-vue'
import { provideA2UI } from '@meldui/a2ui/vue'
import ChatMessageList from '@/components/ChatMessageList.vue'
import ChatComposer from '@/components/ChatComposer.vue'
import EnvelopeInspector from '@/components/EnvelopeInspector.vue'
import { useChatChannel } from '@/composables/useChatChannel'
import { getConversation } from '@/lib/api'
import type { A2UIEnvelope, A2uiClientAction, Conversation, Message } from '@/types/chat'

const props = defineProps<{ id: string }>()

const { messages, streaming, error, envelopes, activities, send, sendAction } = useChatChannel(
  props.id,
)

const conversation = ref<Conversation | null>(null)
const inspectorOpen = ref(false)

onMounted(async () => {
  try {
    conversation.value = await getConversation(props.id)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : String(e))
  }
})

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

// Conversation-wide totals — sum across every assistant row that carries a
// usage rollup. Latency totals the per-turn wall-clock; not the same thing as
// "time on screen" but it's what the blog wants (sum-of-LLM-work).
const totals = computed(() => {
  const list = (messages.value ?? []) as Message[]
  let input = 0
  let output = 0
  let cache = 0
  let latency = 0
  let turns = 0
  for (const msg of list) {
    if (msg.role !== 'assistant') continue
    const u = msg.usage
    if (u) {
      input += numeric(u.input_tokens)
      output += numeric(u.output_tokens)
      cache += numeric(u.cache_read_input_tokens) + numeric(u.cache_creation_input_tokens)
    }
    if (typeof msg.latency_ms === 'number') latency += msg.latency_ms
    if (u || typeof msg.latency_ms === 'number') turns += 1
  }
  return { input, output, cache, latency, turns }
})

function numeric(v: unknown) {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0
}

const envelopeList = computed(() => envelopes.value ?? [])
const showPresets = computed(() => (messages.value ?? []).length === 0)
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
        <span class="text-sm font-medium">
          {{ conversation?.title || 'Conversation' }}
        </span>
        <span class="font-mono text-xs text-muted-foreground">{{ shortId(props.id) }}</span>
      </div>
      <span
        v-if="conversation"
        class="rounded-full bg-muted px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-muted-foreground"
      >{{ conversation.mode }}</span>
      <div
        v-if="totals.turns > 0"
        class="ml-2 hidden font-mono text-[10px] uppercase tracking-wide text-muted-foreground sm:flex sm:items-center sm:gap-1.5"
      >
        <span>in {{ totals.input }}</span>
        <span>·</span>
        <span>out {{ totals.output }}</span>
        <span>·</span>
        <span>cache {{ totals.cache }}</span>
        <span>·</span>
        <span>{{ totals.latency }} ms</span>
      </div>
      <div class="ml-auto">
        <Button variant="ghost" size="sm" @click="inspectorOpen = true">
          <IconCode class="size-4" />
          <span class="ml-1.5 hidden sm:inline">Envelopes · {{ envelopeList.length }}</span>
        </Button>
      </div>
    </header>

    <ChatMessageList
      :messages="messages ?? []"
      :streaming="streaming ?? false"
      :activities="activities ?? []"
    />

    <ChatComposer
      :disabled="streaming ?? false"
      :show-presets="showPresets"
      @submit="send"
    />

    <EnvelopeInspector
      v-model:open="inspectorOpen"
      :envelopes="envelopeList"
    />
  </main>
</template>
