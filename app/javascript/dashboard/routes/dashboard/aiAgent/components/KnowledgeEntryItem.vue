<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { NEEDS_ANSWER } from '../constants';
import { useStatusOptions } from '../useStatusOptions';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  entry: { type: Object, required: true },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();
const { statusLabel } = useStatusOptions();

const STATUS_CLASSES = {
  published: 'bg-n-teal-3 text-n-teal-11',
  draft: 'bg-n-slate-3 text-n-slate-11',
  needs_answer: 'bg-n-amber-3 text-n-amber-11',
};

const askedInfo = computed(() => {
  const {
    status,
    asked_count: count,
    last_asked_at: lastAskedAt,
  } = props.entry;
  if (status !== NEEDS_ANSWER) return '';
  if (!lastAskedAt) {
    return t('AI_AGENT.KNOWLEDGE.LIST.ASKED_COUNT', { count }, count);
  }

  return t(
    'AI_AGENT.KNOWLEDGE.LIST.ASKED_COUNT_WITH_LAST',
    { count, time: dynamicTime(lastAskedAt) },
    count
  );
});
</script>

<template>
  <li class="flex items-start gap-2 py-3">
    <button
      type="button"
      class="flex flex-col flex-1 min-w-0 gap-1.5 p-0 text-start"
      @click="emit('edit', entry)"
    >
      <span class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
        <span class="font-mono font-medium text-n-slate-12">
          {{ entry.key }}
        </span>
        <span
          class="px-1.5 py-0.5 rounded-md font-medium"
          :class="STATUS_CLASSES[entry.status]"
        >
          {{ statusLabel(entry.status) }}
        </span>
        <span v-if="entry.category" class="min-w-0 truncate text-n-slate-11">
          {{ entry.category }}
        </span>
      </span>
      <span class="text-sm break-words line-clamp-2 text-n-slate-12">
        {{ entry.question }}
      </span>
      <span v-if="askedInfo" class="text-xs text-n-amber-11">
        {{ askedInfo }}
      </span>
    </button>
    <Button
      icon="i-lucide-trash-2"
      variant="ghost"
      color="slate"
      size="sm"
      class="flex-shrink-0"
      :aria-label="t('AI_AGENT.KNOWLEDGE.ACTIONS.DELETE')"
      :title="t('AI_AGENT.KNOWLEDGE.ACTIONS.DELETE')"
      @click="emit('delete', entry)"
    />
  </li>
</template>
