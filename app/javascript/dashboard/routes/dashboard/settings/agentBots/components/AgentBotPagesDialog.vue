<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AgentBotsAPI from 'dashboard/api/agentBots';
import { dynamicTime, messageStamp } from 'shared/helpers/timeHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const STATUS_COLORS = {
  pending: 'amber',
  fetched: 'teal',
  failed: 'ruby',
};

const { t } = useI18n();

const dialogRef = ref(null);
const bot = ref({});
const pages = ref([]);
const isFetching = ref(false);
const newPageUrl = ref('');
const newPageUrlError = ref('');
const isAdding = ref(false);
const loadingPageIds = ref({});

const statusLabels = computed(() => ({
  pending: t('AGENT_BOTS.PAGES.STATUS.PENDING'),
  fetched: t('AGENT_BOTS.PAGES.STATUS.FETCHED'),
  failed: t('AGENT_BOTS.PAGES.STATUS.FAILED'),
}));

const isHttpUrl = value => {
  try {
    return ['http:', 'https:'].includes(new URL(value).protocol);
  } catch (error) {
    return false;
  }
};

const apiErrorMessage = (error, fallback) =>
  error?.response?.data?.message || error?.response?.data?.error || fallback;

const fetchPages = async () => {
  isFetching.value = true;
  try {
    const { data } = await AgentBotsAPI.getPages(bot.value.id);
    pages.value = Array.isArray(data) ? data : data.payload;
  } catch (error) {
    useAlert(t('AGENT_BOTS.PAGES.API.FETCH_ERROR'));
  } finally {
    isFetching.value = false;
  }
};

const open = selectedBot => {
  bot.value = selectedBot;
  pages.value = [];
  newPageUrl.value = '';
  newPageUrlError.value = '';
  dialogRef.value.open();
  fetchPages();
};

const addPage = async () => {
  const url = newPageUrl.value.trim();
  if (!isHttpUrl(url)) {
    newPageUrlError.value = t('AGENT_BOTS.PAGES.FORM.INVALID_URL');
    return;
  }

  newPageUrlError.value = '';
  isAdding.value = true;
  try {
    await AgentBotsAPI.createPage(bot.value.id, url);
    newPageUrl.value = '';
    await fetchPages();
  } catch (error) {
    newPageUrlError.value = apiErrorMessage(
      error,
      t('AGENT_BOTS.PAGES.API.ADD_ERROR')
    );
  } finally {
    isAdding.value = false;
  }
};

const refreshPage = async page => {
  loadingPageIds.value[page.id] = true;
  try {
    await AgentBotsAPI.refreshPage(bot.value.id, page.id);
    useAlert(t('AGENT_BOTS.PAGES.REFRESH.SUCCESS_MESSAGE'));
    await fetchPages();
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('AGENT_BOTS.PAGES.REFRESH.ERROR_MESSAGE'))
    );
  } finally {
    loadingPageIds.value[page.id] = false;
  }
};

const deletePage = async page => {
  loadingPageIds.value[page.id] = true;
  try {
    await AgentBotsAPI.deletePage(bot.value.id, page.id);
    pages.value = pages.value.filter(({ id }) => id !== page.id);
    useAlert(t('AGENT_BOTS.PAGES.DELETE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(
      apiErrorMessage(error, t('AGENT_BOTS.PAGES.DELETE.ERROR_MESSAGE'))
    );
  } finally {
    loadingPageIds.value[page.id] = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="xl"
    overflow-y-auto
    :title="t('AGENT_BOTS.PAGES.TITLE')"
    :description="t('AGENT_BOTS.PAGES.DESCRIPTION', { botName: bot.name })"
    :cancel-button-label="t('AGENT_BOTS.PAGES.CLOSE')"
    :show-confirm-button="false"
  >
    <div class="flex flex-col min-w-0 gap-4">
      <form
        novalidate
        class="flex flex-col gap-1"
        @submit.prevent.stop="addPage"
      >
        <label for="agent-bot-page-url" class="mb-0.5">
          {{ t('AGENT_BOTS.PAGES.FORM.LABEL') }}
        </label>
        <div class="flex flex-col gap-2 sm:flex-row sm:items-start">
          <div class="flex-1 min-w-0">
            <Input
              id="agent-bot-page-url"
              v-model="newPageUrl"
              type="url"
              maxlength="2048"
              :placeholder="t('AGENT_BOTS.PAGES.FORM.PLACEHOLDER')"
              :message-type="newPageUrlError ? 'error' : 'info'"
            />
          </div>
          <Button
            type="submit"
            icon="i-lucide-plus"
            class="flex-shrink-0"
            data-test-id="agent-bot-page-add"
            :label="t('AGENT_BOTS.PAGES.FORM.ADD')"
            :is-loading="isAdding"
          />
        </div>
        <p
          v-if="newPageUrlError"
          class="mb-0 break-words text-label-small text-n-ruby-9"
        >
          {{ newPageUrlError }}
        </p>
      </form>

      <div
        v-if="isFetching && !pages.length"
        class="flex items-center justify-center gap-2 py-6 text-sm text-n-slate-11"
      >
        <Spinner :size="16" />
        {{ t('AGENT_BOTS.PAGES.LOADING') }}
      </div>
      <p
        v-else-if="!pages.length"
        class="py-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('AGENT_BOTS.PAGES.EMPTY') }}
      </p>
      <div v-else class="flex flex-col min-w-0 gap-1">
        <div class="flex justify-end">
          <Button
            type="button"
            icon="i-lucide-rotate-cw"
            ghost
            slate
            xs
            data-test-id="agent-bot-pages-reload"
            :label="t('AGENT_BOTS.PAGES.RELOAD')"
            :is-loading="isFetching"
            @click="fetchPages"
          />
        </div>
        <ul
          class="flex flex-col min-w-0 p-0 m-0 list-none divide-y divide-n-weak"
        >
          <li
            v-for="page in pages"
            :key="page.id"
            class="flex flex-col min-w-0 gap-1.5 py-3"
            data-test-id="agent-bot-page"
          >
            <div class="flex items-start min-w-0 gap-2">
              <div class="flex flex-col flex-1 min-w-0 gap-0.5">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ page.title || page.url }}
                </span>
                <a
                  v-if="page.title"
                  :href="page.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs truncate text-n-slate-11 hover:underline"
                >
                  {{ page.url }}
                </a>
              </div>
              <div class="flex items-center flex-shrink-0 gap-1">
                <Button
                  v-tooltip.top="t('AGENT_BOTS.PAGES.REFRESH.BUTTON_TEXT')"
                  type="button"
                  icon="i-lucide-refresh-cw"
                  ghost
                  slate
                  sm
                  data-test-id="agent-bot-page-refresh"
                  :is-loading="loadingPageIds[page.id]"
                  @click="refreshPage(page)"
                />
                <ConfirmButton
                  v-tooltip.top="t('AGENT_BOTS.PAGES.DELETE.BUTTON_TEXT')"
                  icon="i-lucide-trash-2"
                  color="slate"
                  variant="ghost"
                  size="sm"
                  data-test-id="agent-bot-page-delete"
                  :confirm-label="t('AGENT_BOTS.PAGES.DELETE.CONFIRM')"
                  :is-loading="loadingPageIds[page.id]"
                  @click="deletePage(page)"
                />
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <Label
                :label="statusLabels[page.status]"
                :color="STATUS_COLORS[page.status]"
                compact
              />
              <span
                v-if="page.fetched_at"
                class="text-xs text-n-slate-11"
                :title="messageStamp(page.fetched_at, 'LLL d, yyyy h:mm a')"
              >
                {{
                  t('AGENT_BOTS.PAGES.LAST_FETCHED', {
                    time: dynamicTime(page.fetched_at),
                  })
                }}
              </span>
            </div>
            <p
              v-if="page.error_message"
              class="mb-0 text-xs break-words text-n-ruby-11"
            >
              {{ page.error_message }}
            </p>
          </li>
        </ul>
      </div>
    </div>
  </Dialog>
</template>
