<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  bot: { type: Object, default: null },
  bots: { type: Array, default: () => [] },
  showActions: { type: Boolean, default: true },
  isExporting: { type: Boolean, default: false },
});

const emit = defineEmits(['switchBot', 'create', 'import', 'export']);

const { t } = useI18n();

const isSwitcherOpen = ref(false);

const botMenuItems = computed(() =>
  props.bots.map(item => ({
    label: item.name,
    value: item.id,
    action: 'switch',
    isSelected: item.id === props.bot?.id,
    thumbnail: { name: item.name, src: item.thumbnail },
  }))
);

const switchBot = ({ value }) => {
  isSwitcherOpen.value = false;
  if (value !== props.bot?.id) emit('switchBot', value);
};
</script>

<template>
  <header class="px-4 pt-6 pb-2 sm:px-6">
    <div
      class="flex flex-col w-full max-w-5xl gap-4 mx-auto sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-col min-w-0 gap-0.5">
        <OnClickOutside
          class="relative flex items-center min-w-0 gap-1"
          @trigger="isSwitcherOpen = false"
        >
          <h1 class="mb-0 text-xl font-medium truncate text-n-slate-12">
            {{ bot?.name || t('AI_AGENT.KNOWLEDGE.TITLE') }}
          </h1>
          <Button
            v-if="bots.length > 1"
            icon="i-lucide-chevron-down"
            :variant="isSwitcherOpen ? 'faded' : 'ghost'"
            color="slate"
            size="xs"
            class="flex-shrink-0"
            :aria-label="t('AI_AGENT.KNOWLEDGE.SWITCH_BOT')"
            :title="t('AI_AGENT.KNOWLEDGE.SWITCH_BOT')"
            @click="isSwitcherOpen = !isSwitcherOpen"
          />
          <DropdownMenu
            v-if="isSwitcherOpen"
            :menu-items="botMenuItems"
            class="mt-1 top-full ltr:left-0 rtl:right-0 w-64 max-w-full max-h-80"
            @action="switchBot"
          />
        </OnClickOutside>
        <p v-if="bot" class="mb-0 text-sm text-n-slate-11">
          {{ t('AI_AGENT.KNOWLEDGE.TITLE') }}
        </p>
      </div>
      <div v-if="showActions" class="flex flex-wrap items-center gap-2">
        <Button
          :label="t('AI_AGENT.KNOWLEDGE.ACTIONS.IMPORT')"
          icon="i-lucide-upload"
          variant="faded"
          color="slate"
          size="sm"
          @click="emit('import')"
        />
        <Button
          :label="t('AI_AGENT.KNOWLEDGE.ACTIONS.EXPORT')"
          icon="i-lucide-download"
          variant="faded"
          color="slate"
          size="sm"
          :is-loading="isExporting"
          :disabled="isExporting"
          @click="emit('export')"
        />
        <Button
          :label="t('AI_AGENT.KNOWLEDGE.ACTIONS.NEW_ENTRY')"
          icon="i-lucide-plus"
          size="sm"
          @click="emit('create')"
        />
      </div>
    </div>
  </header>
</template>
