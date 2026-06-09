<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { IncremarkContent } from '@incremark/vue'
import { A2UISurface } from '@meldui/a2ui/vue'
import type { Message } from '@/types/chat'

const props = defineProps<{
  messages: Message[]
  streaming: boolean
}>()

const scrollRef = ref<HTMLDivElement | null>(null)
const stickToBottom = ref(true)

const lastMessage = computed(() => props.messages.at(-1) ?? null)

function isLastAssistant(msg: Message) {
  return props.streaming && msg.id === lastMessage.value?.id && msg.role === 'assistant'
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
</script>

<template>
  <div
    ref="scrollRef"
    class="flex-1 overflow-y-auto px-6 py-8"
    @scroll.passive="onScroll"
  >
    <div class="mx-auto flex max-w-2xl flex-col gap-6">
      <template v-for="msg in messages" :key="msg.id">
        <div
          v-if="msg.role === 'user'"
          class="self-end max-w-[85%] rounded-2xl rounded-br-sm bg-primary px-4 py-2.5 text-primary-foreground"
        >
          <p class="whitespace-pre-wrap text-sm leading-relaxed">{{ msg.content }}</p>
        </div>
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
          <div
            v-for="sid in msg.surface_ids ?? []"
            :key="`${msg.id}/${sid}`"
            class="self-start w-full"
          >
            <A2UISurface :surface-id="sid" />
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
