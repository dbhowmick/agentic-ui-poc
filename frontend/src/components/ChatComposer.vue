<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { Button } from '@meldui/vue'
import { IconSend } from '@meldui/tabler-vue'

const props = defineProps<{
  disabled: boolean
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
</script>

<template>
  <div class="border-t bg-background">
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
