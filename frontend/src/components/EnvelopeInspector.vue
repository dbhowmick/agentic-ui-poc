<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  toast,
} from '@meldui/vue'
import { IconCheck, IconCopy } from '@meldui/tabler-vue'
import type { A2UIEnvelope } from '@/types/chat'

const props = defineProps<{
  open: boolean
  envelopes: A2UIEnvelope[]
}>()

const emit = defineEmits<{
  'update:open': [value: boolean]
}>()

type EnvType = 'createSurface' | 'updateComponents' | 'updateDataModel' | 'deleteSurface'

const TYPE_LABELS: Record<EnvType, string> = {
  createSurface: 'create',
  updateComponents: 'components',
  updateDataModel: 'data',
  deleteSurface: 'delete',
}

const ALL_TYPES: EnvType[] = [
  'createSurface',
  'updateComponents',
  'updateDataModel',
  'deleteSurface',
]

const activeTypes = ref<Set<EnvType>>(new Set(ALL_TYPES))

function classify(env: A2UIEnvelope): EnvType | null {
  for (const t of ALL_TYPES) {
    if (env[t]) return t
  }
  return null
}

function surfaceIdOf(env: A2UIEnvelope): string | null {
  return (
    env.createSurface?.surfaceId ??
    env.updateComponents?.surfaceId ??
    env.updateDataModel?.surfaceId ??
    env.deleteSurface?.surfaceId ??
    null
  )
}

// Newest envelope first so a viewer recording a demo sees the most recent
// activity at the top of the panel.
const visible = computed(() => {
  return props.envelopes
    .map((env, index) => ({ env, index, type: classify(env) }))
    .filter((row) => row.type !== null && activeTypes.value.has(row.type))
    .reverse()
})

const counts = computed(() => {
  const out: Record<EnvType, number> = {
    createSurface: 0,
    updateComponents: 0,
    updateDataModel: 0,
    deleteSurface: 0,
  }
  for (const env of props.envelopes) {
    const t = classify(env)
    if (t) out[t] += 1
  }
  return out
})

function toggleType(t: EnvType) {
  const next = new Set(activeTypes.value)
  if (next.has(t)) next.delete(t)
  else next.add(t)
  activeTypes.value = next
}

const justCopied = ref<number | null>(null)
let copyResetTimer: ReturnType<typeof setTimeout> | null = null

async function copy(env: A2UIEnvelope, index: number) {
  try {
    await navigator.clipboard.writeText(JSON.stringify(env, null, 2))
    justCopied.value = index
    if (copyResetTimer) clearTimeout(copyResetTimer)
    copyResetTimer = setTimeout(() => {
      justCopied.value = null
    }, 1500)
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'Copy failed')
  }
}

function onOpenChange(value: boolean) {
  emit('update:open', value)
}

function pretty(env: A2UIEnvelope) {
  return JSON.stringify(env, null, 2)
}
</script>

<template>
  <Sheet :open="open" @update:open="onOpenChange">
    <SheetContent side="right" class="w-full sm:max-w-xl flex flex-col gap-0 p-0">
      <SheetHeader class="border-b px-6 py-4">
        <SheetTitle>A2UI envelopes</SheetTitle>
        <SheetDescription>
          Raw v0.9 envelopes streamed for this conversation, newest first.
        </SheetDescription>
      </SheetHeader>

      <div class="flex flex-wrap gap-1.5 border-b px-6 py-3">
        <button
          v-for="t in ALL_TYPES"
          :key="t"
          type="button"
          class="rounded-full border px-2.5 py-1 font-mono text-[10px] uppercase tracking-wide transition-colors"
          :class="activeTypes.has(t)
            ? 'border-foreground bg-foreground text-background'
            : 'border-border bg-muted/40 text-muted-foreground hover:bg-muted'"
          @click="toggleType(t)"
        >
          {{ TYPE_LABELS[t] }} · {{ counts[t] }}
        </button>
      </div>

      <div class="flex-1 overflow-y-auto px-6 py-4">
        <p
          v-if="visible.length === 0"
          class="py-12 text-center text-sm text-muted-foreground"
        >
          No envelopes match the current filter.
        </p>

        <ul v-else class="flex flex-col gap-3">
          <li
            v-for="row in visible"
            :key="row.index"
            class="rounded-lg border bg-card"
          >
            <div class="flex items-center justify-between border-b px-3 py-2">
              <div class="flex items-center gap-2 text-xs">
                <span class="rounded bg-muted px-1.5 py-0.5 font-mono uppercase tracking-wide text-muted-foreground">
                  {{ TYPE_LABELS[row.type!] }}
                </span>
                <span v-if="surfaceIdOf(row.env)" class="font-mono text-muted-foreground">
                  {{ surfaceIdOf(row.env) }}
                </span>
                <span class="font-mono text-muted-foreground">#{{ row.index }}</span>
              </div>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded px-1.5 py-1 text-xs text-muted-foreground hover:bg-muted hover:text-foreground"
                @click="copy(row.env, row.index)"
              >
                <IconCheck v-if="justCopied === row.index" class="size-3.5" />
                <IconCopy v-else class="size-3.5" />
                {{ justCopied === row.index ? 'copied' : 'copy' }}
              </button>
            </div>
            <pre class="overflow-x-auto px-3 py-2 font-mono text-[11px] leading-relaxed text-foreground">{{ pretty(row.env) }}</pre>
          </li>
        </ul>
      </div>
    </SheetContent>
  </Sheet>
</template>
