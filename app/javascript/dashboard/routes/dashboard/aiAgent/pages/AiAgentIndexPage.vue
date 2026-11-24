<script setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiAgentEmptyState from '../components/AiAgentEmptyState.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();

const knowledgeBases = useMapGetter('aiAgentKnowledge/getKnowledgeBases');
const isLoading = ref(true);

onMounted(async () => {
  await store.dispatch('aiAgentKnowledge/fetchKnowledgeBases');

  const [firstBot] = knowledgeBases.value;
  if (firstBot) {
    router.replace({
      name: 'ai_agent_knowledge',
      params: { accountId: route.params.accountId, botId: firstBot.id },
    });
    return;
  }

  isLoading.value = false;
});
</script>

<template>
  <div
    class="flex items-center justify-center w-full h-full overflow-y-auto bg-n-surface-1"
  >
    <Spinner v-if="isLoading" class="text-n-slate-11" />
    <AiAgentEmptyState
      v-else
      :title="$t('AI_AGENT.INDEX.EMPTY_TITLE')"
      :description="$t('AI_AGENT.INDEX.EMPTY_DESCRIPTION')"
    />
  </div>
</template>
