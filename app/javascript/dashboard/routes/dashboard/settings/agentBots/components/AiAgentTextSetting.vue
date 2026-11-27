<script setup>
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// A text setting of an AI agent bot: blank means the default text, which the
// field shows as its placeholder and can copy in as a starting point.
defineProps({
  id: { type: String, required: true },
  label: { type: String, required: true },
  help: { type: String, required: true },
  defaultText: { type: String, default: '' },
  maxLength: { type: Number, required: true },
  minHeight: { type: String, default: '4rem' },
  maxHeight: { type: String, default: '12rem' },
});

const modelValue = defineModel({ type: String, default: '' });

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex items-center justify-between gap-2 mb-0.5">
      <label :for="id">{{ label }}</label>
      <NextButton
        v-if="!modelValue && defaultText"
        type="button"
        link
        xs
        data-test-id="ai-agent-text-setting-use-default"
        :label="t('AGENT_BOTS.FORM.AI_AGENT.USE_DEFAULT')"
        @click="modelValue = defaultText"
      />
    </div>
    <TextArea
      :id="id"
      v-model="modelValue"
      :placeholder="defaultText"
      :max-length="maxLength"
      show-character-count
      auto-height
      :min-height="minHeight"
      :max-height="maxHeight"
    />
    <p class="mb-0 text-label-small text-n-slate-11">
      {{ help }}
    </p>
  </div>
</template>
