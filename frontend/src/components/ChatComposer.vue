<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { Button } from '@meldui/vue'
import { IconSend } from '@meldui/tabler-vue'
import ScenarioPresets from '@/components/ScenarioPresets.vue'

const props = defineProps<{
  disabled: boolean
  showPresets?: boolean
}>()

const emit = defineEmits<{
  submit: [content: string]
}>()

const text = ref('')
const textareaRef = ref<HTMLTextAreaElement | null>(null)

function autosize() {
  const el = textareaRef.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${Math.min(el.scrollHeight, 220)}px`
}

function submit() {
  const value = text.value.trim()
  if (!value || props.disabled) return
  emit('submit', value)
  text.value = ''
  nextTick(autosize)
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
    e.preventDefault()
    submit()
  }
}

watch(text, () => nextTick(autosize))

// Don't auto-send presets — drop the prompt into the textarea so the user can
// edit the seed before firing, and so a click followed by typing reads as one
// continuous turn rather than two separate sends.
function applyPreset(prompt: string) {
  text.value = prompt
  nextTick(() => {
    autosize()
    textareaRef.value?.focus()
  })
}
</script>

<template>
  <div class="border-t bg-background">
    <div
      v-if="showPresets"
      class="mx-auto max-w-2xl px-6 pt-4"
    >
      <p class="mb-2 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        Try one
      </p>
      <ScenarioPresets @select="applyPreset" />
    </div>
    <form
      class="mx-auto flex max-w-2xl items-end gap-2 px-6 py-4"
      @submit.prevent="submit"
    >
      <textarea
        ref="textareaRef"
        v-model="text"
        rows="1"
        placeholder="Message…"
        class="flex-1 resize-none rounded-xl border border-input bg-background px-3.5 py-2.5 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="disabled"
        @keydown="onKeydown"
      />
      <Button
        type="submit"
        size="icon"
        :disabled="disabled || !text.trim()"
        aria-label="Send"
      >
        <IconSend class="size-4" />
      </Button>
    </form>
  </div>
</template>
