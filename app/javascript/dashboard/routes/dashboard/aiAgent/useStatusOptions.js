import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

export const useStatusOptions = () => {
  const { t } = useI18n();

  const statusOptions = computed(() => [
    { value: 'published', label: t('AI_AGENT.KNOWLEDGE.STATUS.PUBLISHED') },
    { value: 'draft', label: t('AI_AGENT.KNOWLEDGE.STATUS.DRAFT') },
    {
      value: 'needs_answer',
      label: t('AI_AGENT.KNOWLEDGE.STATUS.NEEDS_ANSWER'),
    },
  ]);

  const statusLabel = value =>
    statusOptions.value.find(option => option.value === value)?.label || '';

  return { statusOptions, statusLabel };
};
