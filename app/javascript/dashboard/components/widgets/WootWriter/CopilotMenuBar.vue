<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useElementSize } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';

const props = defineProps({
  hasSelection: {
    type: Boolean,
    default: false,
  },
  isEditorMenuPopover: {
    type: Boolean,
    default: false,
  },
  editorContent: {
    type: String,
    default: undefined,
  },
  conversationId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['executeCopilotAction']);

const { t } = useI18n();

const replyMode = useMapGetter('draftMessages/getReplyEditorMode');

const effectiveContent = computed(() => props.editorContent || '');

const menuItems = computed(() => {
  const items = [];

  if (
    props.conversationId &&
    replyMode.value === REPLY_EDITOR_MODES.REPLY &&
    effectiveContent.value.trim()
  ) {
    items.push({
      label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.PREPARE_ANSWER'),
      key: 'prepare_answer',
      icon: 'i-fluent-pen-sparkle-24-regular',
    });
  }

  if (props.conversationId) {
    items.push({
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ANSWER_FROM_KNOWLEDGE_BASE'
      ),
      key: 'knowledge_answer',
      icon: 'i-fluent-book-search-24-regular',
    });

    items.push({
      label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUMMARIZE'),
      key: 'summarize',
      icon: 'i-fluent-text-bullet-list-square-sparkle-32-regular',
    });
  }

  return items;
});

const menuRef = useTemplateRef('menuRef');
const { height: menuHeight } = useElementSize(menuRef);

// Computed style for selection menu positioning (only dynamic top offset)
const selectionMenuStyle = computed(() => {
  // Dynamically calculate offset based on actual menu height + 10px gap
  const dynamicOffset = menuHeight.value > 0 ? menuHeight.value + 10 : 60;

  return {
    top: `calc(var(--selection-top) - ${dynamicOffset}px)`,
  };
});

const handleMenuItemClick = item => {
  emit('executeCopilotAction', item.key);
};
</script>

<template>
  <DropdownBody
    ref="menuRef"
    class="min-w-56 [&>ul]:gap-3 z-50 [&>ul]:px-4 [&>ul]:py-3.5"
    :class="{ 'selection-menu': hasSelection && isEditorMenuPopover }"
    :style="hasSelection && isEditorMenuPopover ? selectionMenuStyle : {}"
  >
    <div class="flex flex-col items-start gap-2.5">
      <div v-for="item in menuItems" :key="item.key" class="w-full">
        <Button
          :label="item.label"
          :icon="item.icon"
          slate
          link
          sm
          class="hover:!no-underline text-n-slate-12 font-normal text-xs w-full !justify-start"
          @click="handleMenuItemClick(item)"
        />
      </div>
    </div>
  </DropdownBody>
</template>

<style scoped lang="scss">
.selection-menu {
  position: absolute !important;

  // Default/LTR: position from left
  left: var(--selection-left);

  // RTL: position from right instead
  [dir='rtl'] & {
    left: auto;
    right: var(--selection-right);
  }
}
</style>
