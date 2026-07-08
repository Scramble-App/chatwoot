<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const { t } = useI18n();
const isLinking = ref(false);
const isDismissing = ref(false);

const suggestion = computed(
  () => props.chat.additional_attributes?.customer_identity_suggestion || {}
);

const shouldShowBanner = computed(
  () => suggestion.value.status === 'pending' && suggestion.value.email
);

const matchedCustomer = computed(() => {
  if (suggestion.value.matched_contact_name) {
    return `${suggestion.value.matched_contact_name} (${suggestion.value.email})`;
  }

  return suggestion.value.email;
});

const bannerMessage = computed(() =>
  t('CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.MESSAGE', {
    customer: matchedCustomer.value,
  })
);

const handleError = error => {
  const message =
    error?.response?.data?.error ||
    t('CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.ERROR');
  useAlert(message);
};

const linkCustomer = async () => {
  isLinking.value = true;
  try {
    await store.dispatch('linkCustomerIdentitySuggestion', {
      conversationId: props.chat.id,
    });
    useAlert(t('CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.LINK_SUCCESS'));
  } catch (error) {
    handleError(error);
  } finally {
    isLinking.value = false;
  }
};

const dismissSuggestion = async () => {
  isDismissing.value = true;
  try {
    await store.dispatch('dismissCustomerIdentitySuggestion', {
      conversationId: props.chat.id,
    });
  } catch (error) {
    handleError(error);
  } finally {
    isDismissing.value = false;
  }
};
</script>

<template>
  <div
    v-if="shouldShowBanner"
    class="flex flex-col gap-2 px-3 py-2 text-sm border-b md:flex-row md:items-center md:justify-between bg-n-amber-3 border-n-amber-5 text-n-slate-12"
  >
    <span class="min-w-0 break-words">
      {{ bannerMessage }}
    </span>
    <div class="flex items-center flex-shrink-0 gap-2">
      <Button
        xs
        amber
        faded
        icon="i-lucide-link"
        :label="$t('CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.LINK')"
        :disabled="isLinking || isDismissing"
        :is-loading="isLinking"
        @click="linkCustomer"
      />
      <Button
        xs
        slate
        ghost
        icon="i-lucide-x"
        :label="$t('CONVERSATION.CUSTOMER_IDENTITY_SUGGESTION.DISMISS')"
        :disabled="isLinking || isDismissing"
        :is-loading="isDismissing"
        @click="dismissSuggestion"
      />
    </div>
  </div>
  <span v-else />
</template>
