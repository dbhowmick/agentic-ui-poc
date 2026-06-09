<script setup lang="ts">
import { useRoute, RouterView } from 'vue-router'
import { Toaster } from '@meldui/vue'

const route = useRoute()
</script>

<template>
  <RouterView :key="route.path" />
  <Toaster position="bottom-right" />
</template>
