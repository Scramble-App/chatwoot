<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { ENTRY_STATUSES, NEEDS_ANSWER, NO_ACCESS_STATUSES } from '../constants';

import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AiAgentEmptyState from '../components/AiAgentEmptyState.vue';
import DeleteEntryDialog from '../components/DeleteEntryDialog.vue';
import KnowledgeBaseHeader from '../components/KnowledgeBaseHeader.vue';
import KnowledgeEntryDialog from '../components/KnowledgeEntryDialog.vue';
import KnowledgeEntryFilters from '../components/KnowledgeEntryFilters.vue';
import KnowledgeEntryItem from '../components/KnowledgeEntryItem.vue';
import KnowledgeImportDialog from '../components/KnowledgeImportDialog.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const knowledgeBases = useMapGetter('aiAgentKnowledge/getKnowledgeBases');
const entries = useMapGetter('aiAgentKnowledge/getEntries');
const meta = useMapGetter('aiAgentKnowledge/getMeta');
const uiFlags = useMapGetter('aiAgentKnowledge/getUIFlags');

// The filters live in the URL so a filtered list can be shared and survives a reload
const botId = computed(() => Number(route.params.botId));
const status = computed(() =>
  ENTRY_STATUSES.includes(route.query.status) ? route.query.status : ''
);
const category = computed(() => route.query.category || '');
const searchQuery = computed(() => route.query.q || '');
const page = computed(() => Number(route.query.page) || 1);

const searchInput = ref(searchQuery.value);
const hasNoAccess = ref(false);

const entryDialogRef = ref(null);
const deleteDialogRef = ref(null);
const importDialogRef = ref(null);

const currentBot = computed(() =>
  knowledgeBases.value.find(bot => bot.id === botId.value)
);
const hasFilters = computed(
  () => !!(status.value || category.value || searchQuery.value)
);
const isFetching = computed(() => uiFlags.value.isFetching);
const hasSeveralPages = computed(() => meta.value.count > meta.value.perPage);

const updateQuery = changes => {
  const query = { ...route.query, ...changes };
  Object.keys(query).forEach(key => {
    if (!query[key]) delete query[key];
  });
  router.replace({ query });
};

const fetchEntries = async () => {
  try {
    const data = await store.dispatch('aiAgentKnowledge/fetchEntries', {
      botId: botId.value,
      q: searchQuery.value,
      category: category.value,
      status: status.value,
      sort: status.value === NEEDS_ANSWER ? 'asked_count' : undefined,
      page: page.value,
    });
    if (!data) return;

    hasNoAccess.value = false;
    // A deleted last entry or an old link can point past the last page
    const lastPage = Math.ceil(data.meta.count / data.meta.per_page);
    if (!data.payload.length && lastPage && page.value > lastPage) {
      updateQuery({ page: lastPage > 1 ? lastPage : undefined });
    }
  } catch (error) {
    if (NO_ACCESS_STATUSES.includes(error.response?.status)) {
      hasNoAccess.value = true;
    } else {
      useAlert(t('AI_AGENT.KNOWLEDGE.LIST.FETCH_ERROR'));
    }
  }
};

const SEARCH_DELAY = 400;
let searchTimer = null;

const onSearch = value => {
  searchInput.value = value;
  clearTimeout(searchTimer);
  searchTimer = setTimeout(
    () => updateQuery({ q: value.trim(), page: undefined }),
    SEARCH_DELAY
  );
};

const onStatusChange = value => updateQuery({ status: value, page: undefined });

const onCategoryChange = value =>
  updateQuery({ category: value, page: undefined });

const onPageChange = value => updateQuery({ page: value > 1 ? value : '' });

const switchBot = id => {
  router.replace({
    name: 'ai_agent_knowledge',
    params: { accountId: route.params.accountId, botId: id },
  });
};

const exportEntries = async () => {
  try {
    await store.dispatch('aiAgentKnowledge/exportEntries', {
      botId: botId.value,
    });
  } catch (error) {
    useAlert(t('AI_AGENT.KNOWLEDGE.EXPORT_ERROR'));
  }
};

watch(
  [botId, status, category, searchQuery, page],
  ([newBotId], oldValues) => {
    if (!oldValues || newBotId !== oldValues[0]) {
      clearTimeout(searchTimer);
      hasNoAccess.value = false;
      store.dispatch('aiAgentKnowledge/resetEntries');
    }
    fetchEntries();
  },
  { immediate: true }
);

watch(searchQuery, value => {
  if (value !== searchInput.value.trim()) searchInput.value = value;
});

// Picks up bots created or shared since the sidebar loaded the list
onMounted(() => store.dispatch('aiAgentKnowledge/fetchKnowledgeBases'));

onBeforeUnmount(() => clearTimeout(searchTimer));
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <KnowledgeBaseHeader
      :bot="currentBot"
      :bots="knowledgeBases"
      :show-actions="!hasNoAccess"
      :is-exporting="uiFlags.isExporting"
      @switch-bot="switchBot"
      @create="entryDialogRef.open()"
      @import="importDialogRef.open()"
      @export="exportEntries"
    />
    <main class="flex-1 min-h-0 px-4 overflow-y-auto sm:px-6">
      <div class="w-full max-w-5xl py-4 mx-auto">
        <AiAgentEmptyState
          v-if="hasNoAccess"
          icon="i-lucide-lock-keyhole"
          :title="t('AI_AGENT.KNOWLEDGE.NO_ACCESS.TITLE')"
          :description="t('AI_AGENT.KNOWLEDGE.NO_ACCESS.DESCRIPTION')"
        />
        <template v-else>
          <KnowledgeEntryFilters
            :status="status"
            :category="category"
            :search="searchInput"
            :status-counts="meta.statusCounts"
            :categories="meta.categories"
            @update:status="onStatusChange"
            @update:category="onCategoryChange"
            @update:search="onSearch"
          />
          <div
            v-if="isFetching && !entries.length"
            class="flex justify-center py-10 text-n-slate-11"
          >
            <Spinner />
          </div>
          <AiAgentEmptyState
            v-else-if="!entries.length && hasFilters"
            icon="i-lucide-search-x"
            :title="t('AI_AGENT.KNOWLEDGE.LIST.NO_RESULTS_TITLE')"
            :description="t('AI_AGENT.KNOWLEDGE.LIST.NO_RESULTS_DESCRIPTION')"
          />
          <AiAgentEmptyState
            v-else-if="!entries.length"
            icon="i-lucide-book-open"
            :title="t('AI_AGENT.KNOWLEDGE.LIST.EMPTY_TITLE')"
            :description="t('AI_AGENT.KNOWLEDGE.LIST.EMPTY_DESCRIPTION')"
          />
          <ul
            v-else
            class="p-0 m-0 list-none divide-y divide-n-weak transition-opacity"
            :class="{ 'opacity-60': isFetching }"
          >
            <KnowledgeEntryItem
              v-for="entry in entries"
              :key="entry.id"
              :entry="entry"
              @edit="entryDialogRef.open($event)"
              @delete="deleteDialogRef.open($event)"
            />
          </ul>
        </template>
      </div>
    </main>
    <footer
      v-if="!hasNoAccess && entries.length && hasSeveralPages"
      class="sticky bottom-0 z-10"
    >
      <PaginationFooter
        current-page-info="AI_AGENT.KNOWLEDGE.PAGINATION_FOOTER.SHOWING"
        :current-page="meta.currentPage"
        :total-items="meta.count"
        :items-per-page="meta.perPage"
        @update:current-page="onPageChange"
      />
    </footer>
    <!-- Keyed by bot, so a bot change (switcher or browser back) closes them -->
    <KnowledgeEntryDialog
      :key="`entry-${botId}`"
      ref="entryDialogRef"
      :bot-id="botId"
      :categories="meta.categories"
      @saved="fetchEntries"
    />
    <DeleteEntryDialog
      :key="`delete-${botId}`"
      ref="deleteDialogRef"
      :bot-id="botId"
      @deleted="fetchEntries"
    />
    <KnowledgeImportDialog
      :key="`import-${botId}`"
      ref="importDialogRef"
      :bot-id="botId"
      @imported="fetchEntries"
    />
  </section>
</template>
