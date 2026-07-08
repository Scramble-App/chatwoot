<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const {
  content,
  attachments,
  contentAttributes,
  messageType,
  operatorTranslation,
} = useMessageContext();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);

const hasOperatorTranslation = computed(() => {
  return (
    messageType.value === MESSAGE_TYPES.INCOMING &&
    operatorTranslation.value?.content
  );
});

const renderContent = computed(() => {
  if (hasOperatorTranslation.value) {
    return content.value;
  }

  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <div
        v-if="hasOperatorTranslation"
        class="rounded-md border border-n-weak bg-n-alpha-2 px-3 py-2 text-n-slate-12"
      >
        <div class="mb-1 text-xs font-medium uppercase text-n-slate-11">
          {{ $t('CONVERSATION.OPERATOR_TRANSLATION.LABEL') }}
        </div>
        <FormattedContent :content="operatorTranslation.content" />
      </div>
      <TranslationToggle
        v-if="hasTranslations && !hasOperatorTranslation"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
