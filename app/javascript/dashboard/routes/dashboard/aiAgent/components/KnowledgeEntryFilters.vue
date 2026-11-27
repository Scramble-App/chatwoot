<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStatusOptions } from '../useStatusOptions';

import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  status: { type: String, default: '' },
  category: { type: String, default: '' },
  search: { type: String, default: '' },
  statusCounts: { type: Object, required: true },
  categories: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:status', 'update:category', 'update:search']);

const { t } = useI18n();
const { statusOptions } = useStatusOptions();

const statusFilters = computed(() => [
  {
    value: '',
    label: t('AI_AGENT.KNOWLEDGE.FILTERS.ALL'),
    count: statusOptions.value.reduce(
      (total, option) => total + props.statusCounts[option.value],
      0
    ),
  },
  ...statusOptions.value.map(option => ({
    ...option,
    count: props.statusCounts[option.value],
  })),
]);

const categoryOptions = computed(() => [
  { value: '', label: t('AI_AGENT.KNOWLEDGE.FILTERS.ALL_CATEGORIES') },
  ...props.categories.map(name => ({ value: name, label: name })),
]);
</script>

<template>
  <div class="flex flex-col gap-3 mb-2">
    <div
      class="flex flex-wrap gap-2"
      role="group"
      :aria-label="t('AI_AGENT.KNOWLEDGE.FILTERS.STATUS_LABEL')"
    >
      <Button
        v-for="filter in statusFilters"
        :key="filter.value"
        size="sm"
        :variant="status === filter.value ? 'faded' : 'ghost'"
        :color="status === filter.value ? 'blue' : 'slate'"
        :aria-pressed="status === filter.value"
        @click="emit('update:status', filter.value)"
      >
        <span>{{ filter.label }}</span>
        <span class="tabular-nums text-n-slate-11">{{ filter.count }}</span>
      </Button>
    </div>
    <div class="flex flex-col gap-2 sm:flex-row">
      <div class="flex-1 min-w-0">
        <Input
          :model-value="search"
          type="search"
          :placeholder="t('AI_AGENT.KNOWLEDGE.FILTERS.SEARCH_PLACEHOLDER')"
          custom-input-class="ltr:!pl-9 rtl:!pr-9"
          @update:model-value="emit('update:search', $event)"
        >
          <template #prefix>
            <Icon
              icon="i-lucide-search"
              class="absolute -translate-y-1/2 pointer-events-none top-1/2 ltr:left-3 rtl:right-3 size-4 text-n-slate-10"
            />
          </template>
        </Input>
      </div>
      <div v-if="categories.length" class="w-full sm:w-56 sm:flex-shrink-0">
        <ComboBox
          :model-value="category"
          :options="categoryOptions"
          :search-placeholder="
            t('AI_AGENT.KNOWLEDGE.FILTERS.CATEGORY_SEARCH_PLACEHOLDER')
          "
          @update:model-value="emit('update:category', $event)"
        />
      </div>
    </div>
  </div>
</template>
