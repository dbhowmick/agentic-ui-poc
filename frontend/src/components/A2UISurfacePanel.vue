<script setup lang="ts">
import { toRaw } from 'vue'
import { A2UISurface, provideA2UI } from '@meldui/a2ui/vue'
import type { A2UIEnvelope } from '@/types/chat'

const props = defineProps<{
  envelopes: A2UIEnvelope[]
  surfaceId: string
  onAction: (a: unknown) => void
}>()

// Provide a FRESH `MessageProcessor` on every mount. The parent (ChatView)
// keys this component on the envelope-log length, so every new envelope
// remounts this component and recreates the processor from scratch. That
// works around two related issues in `@meldui/a2ui@0.1.0`:
//
//   - `useA2uiNode` subscribes to `componentsModel.onCreated/onDeleted` but
//     NOT to `ComponentModel.onUpdated`, so updating an existing component's
//     literal props doesn't re-render in Vue.
//   - `<A2UISurface>` keys its inner `<DeferredChild>` by `surface.id`, so
//     even when the surface is deleted + recreated in place, Vue reuses the
//     same `DeferredChild` instance and its `useA2uiNode` subscriptions stay
//     bound to the old (now-disposed) `componentsModel`.
//
// By forcing a full unmount/remount via a parent `:key`, both subscriptions
// and Vue's vnode tree are rebuilt cleanly. The trade-off is a brief flicker
// on each new envelope and replaying the full log every time — acceptable
// for Phase 3 envelope volumes.
const { processor } = provideA2UI({ onAction: props.onAction })

// Defensive replay:
//   1. `toRaw` to strip Vue reactive proxies before handing envelopes to the
//      processor — `MessageProcessor` uses `'key' in message` checks and
//      destructuring that can misbehave on proxies in some Vue paths.
//   2. Drop duplicate `createSurface` envelopes for the same `surfaceId` —
//      the upstream processor throws `A2uiStateError: Surface ... already
//      exists` instead of being idempotent, and persisted+broadcast paths
//      can converge on duplicates if a turn re-issues `create_surface`.
//   3. Drop `updateComponents`/`updateDataModel` envelopes that reference a
//      surface we never saw a `createSurface` for in this log — those throw
//      `Surface not found` and would abort the rest of the replay.
//   4. Wrap the call in try/catch so one bad envelope can't blank the panel.
function buildReplayBatch(envs: A2UIEnvelope[]): A2UIEnvelope[] {
  const seenCreate = new Set<string>()
  const result: A2UIEnvelope[] = []
  for (const env of envs.map((e) => toRaw(e))) {
    const cs = env.createSurface
    if (cs) {
      if (seenCreate.has(cs.surfaceId)) continue
      seenCreate.add(cs.surfaceId)
      result.push(env)
      continue
    }
    const uc = env.updateComponents
    const udm = env.updateDataModel
    const ds = env.deleteSurface
    const targetSid = uc?.surfaceId ?? udm?.surfaceId ?? ds?.surfaceId
    if (targetSid && !seenCreate.has(targetSid)) continue
    result.push(env)
  }
  return result
}

if (props.envelopes.length > 0) {
  const batch = buildReplayBatch(props.envelopes)
  if (batch.length > 0) {
    try {
      processor.processMessages(batch as Parameters<typeof processor.processMessages>[0])
    } catch (err) {
      console.warn('[A2UISurfacePanel] processMessages failed', err, batch)
    }
  }
}
</script>

<template>
  <A2UISurface :surface-id="surfaceId" />
</template>
