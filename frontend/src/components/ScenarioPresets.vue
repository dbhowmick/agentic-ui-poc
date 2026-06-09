<script setup lang="ts">
import {
  IconChartLine,
  IconLayoutDashboard,
  IconForms,
  IconMarkdown,
} from '@meldui/tabler-vue'
import type { Component } from 'vue'

// Hand-picked prompts that exercise one tier each of the MeldUI catalog —
// structural (Dashboard, Form), rich (Chart), and basic (Markdown). The blog
// uses these as one-click reproductions of the canonical demo turns.
interface Preset {
  key: string
  label: string
  icon: Component
  prompt: string
}

const PRESETS: Preset[] = [
  {
    key: 'dashboard',
    label: 'Dashboard',
    icon: IconLayoutDashboard,
    prompt:
      'Build me a Q3 sales dashboard with four KPI tiles (revenue, new customers, churn, ARR) and a monthly trend chart underneath.',
  },
  {
    key: 'form',
    label: 'Form',
    icon: IconForms,
    prompt:
      'Render a registration form with fields for name, email, a role dropdown (engineer / designer / PM), and a submit button.',
  },
  {
    key: 'markdown',
    label: 'Markdown report',
    icon: IconMarkdown,
    prompt:
      'Write a short markdown report on this quarter’s wins — three sections, a bullet list under each. Render it inside a card surface.',
  },
  {
    key: 'chart',
    label: 'Chart',
    icon: IconChartLine,
    prompt:
      'Plot monthly active users for the last six months as a line chart. Make up plausible numbers around 12k–18k.',
  },
]

defineEmits<{
  select: [prompt: string]
}>()
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="preset in PRESETS"
      :key="preset.key"
      type="button"
      class="inline-flex items-center gap-1.5 rounded-full border bg-card px-3 py-1.5 text-xs text-foreground shadow-sm transition-colors hover:bg-muted/60"
      @click="$emit('select', preset.prompt)"
    >
      <component :is="preset.icon" class="size-3.5 text-muted-foreground" />
      {{ preset.label }}
    </button>
  </div>
</template>
