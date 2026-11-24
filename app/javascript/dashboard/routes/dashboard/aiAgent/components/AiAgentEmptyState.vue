<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  icon: { type: String, default: 'i-lucide-bot' },
  title: { type: String, required: true },
  description: { type: String, default: '' },
});
</script>

<template>
  <div class="flex flex-col items-center gap-3 px-4 py-16 text-center">
    <Icon :icon="icon" class="size-8 text-n-slate-10" />
    <h2 class="mb-0 text-base font-medium text-n-slate-12">{{ title }}</h2>
    <p v-if="description" class="max-w-md mb-0 text-sm text-n-slate-11">
      {{ description }}
    </p>
  </div>
</template>
