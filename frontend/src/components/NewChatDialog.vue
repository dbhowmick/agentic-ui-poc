<script setup lang="ts">
import { ref, watch } from "vue";
import {
  Button,
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  Input,
  Label,
  Tabs,
  TabsList,
  TabsTrigger,
} from "@meldui/vue";
import type { ConversationMode } from "@/types/chat";

const props = defineProps<{
  open: boolean;
  submitting?: boolean;
  defaultModel?: string;
}>();

const emit = defineEmits<{
  (e: "update:open", value: boolean): void;
  (e: "create", payload: { mode: ConversationMode; model: string; title: string | null }): void;
}>();

const DEFAULT_MODEL = "claude-sonnet-4-5-20250929";

const mode = ref<ConversationMode>("tool_calls");
const model = ref(props.defaultModel ?? DEFAULT_MODEL);
const title = ref("");

// Reset the form whenever the dialog opens so a previous half-filled draft
// doesn't bleed into a fresh "New chat" click.
watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      mode.value = "tool_calls";
      model.value = props.defaultModel ?? DEFAULT_MODEL;
      title.value = "";
    }
  },
);

function onOpenChange(value: boolean) {
  emit("update:open", value);
}

function submit() {
  const trimmedModel = model.value.trim() || DEFAULT_MODEL;
  const trimmedTitle = title.value.trim();
  emit("create", {
    mode: mode.value,
    model: trimmedModel,
    title: trimmedTitle === "" ? null : trimmedTitle,
  });
}
</script>

<template>
  <Dialog :open="open" @update:open="onOpenChange">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>New chat</DialogTitle>
        <DialogDescription>
          Pick how Claude should emit A2UI envelopes for this conversation.
        </DialogDescription>
      </DialogHeader>

      <form class="flex flex-col gap-4" @submit.prevent="submit">
        <div class="flex flex-col gap-2">
          <Label for="new-chat-title">Title (optional)</Label>
          <Input
            id="new-chat-title"
            v-model="title"
            placeholder="e.g. Sales dashboard demo"
            autocomplete="off"
          />
        </div>

        <div class="flex flex-col gap-2">
          <Label>Emission mode</Label>
          <Tabs v-model="mode" class="w-full">
            <TabsList class="grid w-full grid-cols-2">
              <TabsTrigger value="tool_calls">tool_calls</TabsTrigger>
              <TabsTrigger value="streamed_json">streamed_json</TabsTrigger>
            </TabsList>
          </Tabs>
          <p class="text-xs text-muted-foreground">
            <span v-if="mode === 'tool_calls'">
              Claude calls four A2UI tools. Each tool call ships a fully-formed envelope.
            </span>
            <span v-else>
              Claude writes A2UI envelopes as JSONL in its message body — one envelope per line.
            </span>
          </p>
        </div>

        <div class="flex flex-col gap-2">
          <Label for="new-chat-model">Model</Label>
          <Input id="new-chat-model" v-model="model" spellcheck="false" autocomplete="off" />
        </div>

        <DialogFooter>
          <Button type="button" variant="ghost" @click="onOpenChange(false)"> Cancel </Button>
          <Button type="submit" :disabled="submitting">
            {{ submitting ? "Creating…" : "Create chat" }}
          </Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
