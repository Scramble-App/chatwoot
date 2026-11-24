<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AgentBotModal from './components/AgentBotModal.vue';
import AgentBotPagesDialog from './components/AgentBotPagesDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const agentBots = useMapGetter('agentBots/getBots');
const uiFlags = useMapGetter('agentBots/getUIFlags');

const selectedBot = ref({});
const searchQuery = ref('');
const loading = ref({});
const modalType = ref(MODAL_TYPES.CREATE);
const agentBotModalRef = ref(null);
const agentBotDeleteDialogRef = ref(null);
const agentBotPagesDialogRef = ref(null);

const tableHeaders = computed(() => {
  return [
    t('AGENT_BOTS.LIST.TABLE_HEADER.DETAILS'),
    t('AGENT_BOTS.LIST.TABLE_HEADER.TYPE'),
    t('AGENT_BOTS.LIST.TABLE_HEADER.ACTIONS'),
  ];
});

const isAiAgentBot = bot => bot.bot_type === 'ai_agent';

const hasAiAgentBots = computed(() => agentBots.value.some(isAiAgentBot));

const selectedBotName = computed(() => selectedBot.value?.name || '');

const filteredAgentBots = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return agentBots.value;
  return picoSearch(agentBots.value, query, ['name', 'description']);
});

const openAddModal = () => {
  modalType.value = MODAL_TYPES.CREATE;
  selectedBot.value = {};
  agentBotModalRef.value.dialogRef.open();
};

const openEditModal = bot => {
  modalType.value = MODAL_TYPES.EDIT;
  selectedBot.value = bot;
  agentBotModalRef.value.dialogRef.open();
};

const openDeletePopup = bot => {
  selectedBot.value = bot;
  agentBotDeleteDialogRef.value.open();
};

const openPagesDialog = bot => {
  agentBotPagesDialogRef.value.open(bot);
};

const openKnowledgeBase = bot => {
  router.push({
    name: 'ai_agent_knowledge',
    params: { accountId: route.params.accountId, botId: bot.id },
  });
};

const deleteAgentBot = async id => {
  try {
    await store.dispatch('agentBots/delete', id);
    useAlert(t('AGENT_BOTS.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_BOTS.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[id] = false;
    selectedBot.value = {};
  }
};

const confirmDeletion = () => {
  loading.value[selectedBot.value.id] = true;
  deleteAgentBot(selectedBot.value.id);
  agentBotDeleteDialogRef.value.close();
};

onMounted(() => {
  store.dispatch('agentBots/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('AGENT_BOTS.LIST.LOADING')"
    :no-records-found="!agentBots.length"
    :no-records-message="t('AGENT_BOTS.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('AGENT_BOTS.HEADER')"
        :description="t('AGENT_BOTS.DESCRIPTION')"
        :link-text="t('AGENT_BOTS.LEARN_MORE')"
        :search-placeholder="t('AGENT_BOTS.SEARCH_PLACEHOLDER')"
        feature-name="agent_bots"
      >
        <template v-if="agentBots?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('AGENT_BOTS.COUNT', { n: agentBots.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('AGENT_BOTS.ADD.TITLE')"
            size="sm"
            @click="openAddModal"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="filteredAgentBots"
        :no-data-message="
          searchQuery ? t('AGENT_BOTS.NO_RESULTS') : t('AGENT_BOTS.LIST.404')
        "
      >
        <template #row="{ items }">
          <BaseTableRow v-for="bot in items" :key="bot.id" :item="bot">
            <template #default>
              <BaseTableCell class="max-w-0">
                <div class="flex items-center gap-4 min-w-0">
                  <Avatar
                    :name="bot.name"
                    :src="bot.thumbnail"
                    :size="40"
                    class="flex-shrink-0"
                  />
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="text-body-main text-n-slate-12 truncate">
                        {{ bot.name }}
                      </span>
                      <span
                        v-if="bot.system_bot"
                        class="text-xs text-n-slate-12 bg-n-blue-5 rounded-md py-0.5 px-1 flex-shrink-0"
                      >
                        {{ $t('AGENT_BOTS.GLOBAL_BOT_BADGE') }}
                      </span>
                    </div>
                    <span class="text-body-main text-n-slate-11 block truncate">
                      {{ bot.description }}
                    </span>
                  </div>
                </div>
              </BaseTableCell>

              <BaseTableCell class="max-w-0">
                <span
                  class="text-body-main text-n-slate-12 truncate block"
                  data-test-id="agent-bot-type"
                >
                  {{
                    isAiAgentBot(bot)
                      ? t('AGENT_BOTS.TYPES.AI_AGENT')
                      : t('AGENT_BOTS.TYPES.WEBHOOK')
                  }}
                </span>
                <span
                  v-if="!isAiAgentBot(bot)"
                  class="text-body-main text-n-slate-11 truncate block"
                >
                  {{ bot.outgoing_url || bot.bot_config?.webhook_url }}
                </span>
              </BaseTableCell>

              <BaseTableCell
                align="end"
                class="w-24"
                :class="{ 'md:w-48': hasAiAgentBots }"
              >
                <div class="flex flex-wrap gap-3 justify-end">
                  <template v-if="isAiAgentBot(bot)">
                    <Button
                      v-tooltip.top="t('AGENT_BOTS.PAGES.BUTTON_TEXT')"
                      icon="i-lucide-globe"
                      slate
                      sm
                      data-test-id="agent-bot-pages"
                      @click="openPagesDialog(bot)"
                    />
                    <Button
                      v-tooltip.top="t('AGENT_BOTS.KNOWLEDGE_BASE.BUTTON_TEXT')"
                      icon="i-lucide-book-open"
                      slate
                      sm
                      data-test-id="agent-bot-knowledge-base"
                      @click="openKnowledgeBase(bot)"
                    />
                  </template>
                  <Button
                    v-if="!bot.system_bot"
                    v-tooltip.top="t('AGENT_BOTS.EDIT.BUTTON_TEXT')"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    :is-loading="loading[bot.id]"
                    @click="openEditModal(bot)"
                  />
                  <Button
                    v-if="!bot.system_bot"
                    v-tooltip.top="t('AGENT_BOTS.DELETE.BUTTON_TEXT')"
                    icon="i-woot-bin"
                    slate
                    sm
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    :is-loading="loading[bot.id]"
                    @click="openDeletePopup(bot)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <AgentBotModal
      ref="agentBotModalRef"
      :type="modalType"
      :selected-bot="selectedBot"
    />

    <AgentBotPagesDialog ref="agentBotPagesDialogRef" />

    <Dialog
      ref="agentBotDeleteDialogRef"
      type="alert"
      :title="t('AGENT_BOTS.DELETE.CONFIRM.TITLE')"
      :description="
        t('AGENT_BOTS.DELETE.CONFIRM.MESSAGE', { name: selectedBotName })
      "
      :is-loading="uiFlags.isDeleting"
      :confirm-button-label="t('AGENT_BOTS.DELETE.CONFIRM.YES')"
      :cancel-button-label="t('AGENT_BOTS.DELETE.CONFIRM.NO')"
      @confirm="confirmDeletion"
    />
  </SettingsLayout>
</template>
