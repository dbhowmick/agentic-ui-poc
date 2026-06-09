<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { IncremarkContent } from '@incremark/vue'
import { A2UISurface } from '@meldui/a2ui/vue'
import { IconHandClick } from '@meldui/tabler-vue'
import type { A2uiClientAction, Message, UsageStats } from '@/types/chat'

const props = defineProps<{
  messages: Message[]
  streaming: boolean
}>()

const scrollRef = ref<HTMLDivElement | null>(null)
const stickToBottom = ref(true)

const lastMessage = computed(() => props.messages.at(-1) ?? null)

// Each surface renders at the *latest* assistant message whose `surface_ids`
// includes it. Walk messages forward — the last write wins, which is exactly
// the most-recent touching turn. When the user resubmits a form, the backend
// stamps the new assistant row's `surface_ids` with that surface, the streaming
// composable mirrors it live, and this map's value shifts from message #N to
// message #N+1 — so the rendered surface "follows" the conversation downward
// instead of staying pinned at its first appearance way up the page.
const surfaceOwner = computed(() => {
  const owner = new Map<string, string>()
  for (const msg of props.messages) {
    if (msg.role !== 'assistant') continue
    for (const sid of msg.surface_ids ?? []) {
      owner.set(sid, msg.id)
    }
  }
  return owner
})

function isLastAssistant(msg: Message) {
  return props.streaming && msg.id === lastMessage.value?.id && msg.role === 'assistant'
}

// Messages synthesised from a client-side A2UI action are persisted as
// `role: "user"` with content prefixed by `[a2ui_action]` and the structured
// payload stuffed into `tool_results[0]` (see `AgenticUi.A2UI.ClientAction`).
// Render them as a compact chip rather than raw synthesised text so the
// thread reads naturally.
function asActionPayload(msg: Message): A2uiClientAction | null {
  if (msg.role !== 'user') return null
  if (typeof msg.content !== 'string' || !msg.content.startsWith('[a2ui_action]')) return null
  const first = msg.tool_results?.[0]
  if (!first || typeof first !== 'object') return null
  const a = first as Record<string, unknown>
  if (
    typeof a.name !== 'string' ||
    typeof a.surfaceId !== 'string' ||
    typeof a.sourceComponentId !== 'string'
  ) {
    return null
  }
  return a as unknown as A2uiClientAction
}

function onScroll() {
  const el = scrollRef.value
  if (!el) return
  const distanceFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight
  stickToBottom.value = distanceFromBottom < 80
}

async function scrollToBottom() {
  await nextTick()
  const el = scrollRef.value
  if (!el) return
  el.scrollTop = el.scrollHeight
}

watch(
  () => [props.messages.length, props.messages.at(-1)?.content],
  () => {
    if (stickToBottom.value) scrollToBottom()
  },
)

onMounted(scrollToBottom)

// Footer formatting. Backend hands back the upstream `Jido.AI.Usage` shape with
// atom keys ("input_tokens", "output_tokens", "cache_creation_input_tokens",
// "cache_read_input_tokens"). We surface input/output as the headline numbers
// and roll the two cache counters into a single "cache" figure — the blog cares
// about cache-effectiveness, not the read-vs-write split.
function usageInts(u: UsageStats | null | undefined) {
  if (!u) return null
  const input = numeric(u.input_tokens)
  const output = numeric(u.output_tokens)
  const cache = numeric(u.cache_read_input_tokens) + numeric(u.cache_creation_input_tokens)
  if (input === 0 && output === 0 && cache === 0) return null
  return { input, output, cache }
}

function numeric(v: unknown) {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0
}

function hasFooter(msg: Message) {
  return msg.role === 'assistant' && (usageInts(msg.usage) !== null || typeof msg.latency_ms === 'number')
}
</script>

<template>
  <div
    ref="scrollRef"
    class="flex-1 overflow-y-auto px-6 py-8"
    @scroll.passive="onScroll"
  >
    <div class="mx-auto flex max-w-2xl flex-col gap-6">
      <template v-for="msg in messages" :key="msg.id">
        <template v-if="msg.role === 'user'">
          <div
            v-if="asActionPayload(msg)"
            class="self-end inline-flex items-center gap-2 rounded-full border bg-muted/60 px-3 py-1.5 text-xs text-muted-foreground"
            :title="`surface=${asActionPayload(msg)!.surfaceId}\nsource=${asActionPayload(msg)!.sourceComponentId}`"
          >
            <IconHandClick class="size-3.5" />
            <span class="font-medium text-foreground">{{ asActionPayload(msg)!.name }}</span>
            <span class="font-mono">{{ asActionPayload(msg)!.sourceComponentId }}</span>
          </div>
          <div
            v-else
            class="self-end max-w-[85%] rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-primary-foreground"
          >
            <p class="whitespace-pre-wrap text-sm leading-relaxed">{{ msg.content }}</p>
          </div>
        </template>
        <template v-else-if="msg.role === 'assistant'">
          <div
            v-if="msg.content"
            class="markdown-body self-start max-w-[85%] text-sm leading-relaxed text-foreground"
          >
            <IncremarkContent
              :content="msg.content ?? ''"
              :is-finished="!isLastAssistant(msg)"
            />
          </div>
          <template v-for="sid in msg.surface_ids ?? []" :key="`${msg.id}/${sid}`">
            <div
              v-if="surfaceOwner.get(sid) === msg.id"
              class="self-start w-full"
            >
              <A2UISurface :surface-id="sid" />
            </div>
          </template>
          <div
            v-if="hasFooter(msg)"
            class="self-start font-mono text-[10px] uppercase tracking-wide text-muted-foreground"
          >
            <template v-if="usageInts(msg.usage)">
              <span>in {{ usageInts(msg.usage)!.input }}</span>
              <span class="mx-1.5">·</span>
              <span>out {{ usageInts(msg.usage)!.output }}</span>
              <span class="mx-1.5">·</span>
              <span>cache {{ usageInts(msg.usage)!.cache }}</span>
            </template>
            <template v-if="typeof msg.latency_ms === 'number'">
              <span v-if="usageInts(msg.usage)" class="mx-1.5">·</span>
              <span>{{ msg.latency_ms }} ms</span>
            </template>
          </div>
        </template>
      </template>

      <div v-if="streaming && messages.at(-1)?.role !== 'assistant'"
        class="self-start text-sm text-muted-foreground italic"
      >
        Thinking…
      </div>
    </div>
  </div>
</template>

<style scoped>
.markdown-body :deep(p) {
  margin: 0 0 0.75rem;
}
.markdown-body :deep(p:last-child) {
  margin-bottom: 0;
}
.markdown-body :deep(ul),
.markdown-body :deep(ol) {
  margin: 0 0 0.75rem;
  padding-left: 1.25rem;
}
.markdown-body :deep(ul) { list-style: disc; }
.markdown-body :deep(ol) { list-style: decimal; }
.markdown-body :deep(li) { margin-bottom: 0.25rem; }
.markdown-body :deep(h1),
.markdown-body :deep(h2),
.markdown-body :deep(h3),
.markdown-body :deep(h4) {
  font-weight: 600;
  margin: 1rem 0 0.5rem;
  line-height: 1.3;
}
.markdown-body :deep(h1) { font-size: 1.25rem; }
.markdown-body :deep(h2) { font-size: 1.125rem; }
.markdown-body :deep(h3) { font-size: 1rem; }
.markdown-body :deep(code) {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.85em;
  padding: 0.1em 0.35em;
  border-radius: 0.25rem;
  background: var(--color-muted, rgba(0,0,0,0.06));
}
.markdown-body :deep(pre) {
  margin: 0 0 0.75rem;
  padding: 0.75rem;
  border-radius: 0.5rem;
  background: var(--color-muted, rgba(0,0,0,0.06));
  overflow-x: auto;
}
.markdown-body :deep(pre code) {
  padding: 0;
  background: transparent;
}
.markdown-body :deep(a) {
  color: var(--color-primary, #2563eb);
  text-decoration: underline;
  text-underline-offset: 2px;
}
.markdown-body :deep(blockquote) {
  margin: 0 0 0.75rem;
  padding-left: 0.75rem;
  border-left: 3px solid var(--color-border, rgba(0,0,0,0.15));
  color: var(--color-muted-foreground, rgba(0,0,0,0.7));
}
.markdown-body :deep(strong) { font-weight: 600; }
.markdown-body :deep(em) { font-style: italic; }
</style>
