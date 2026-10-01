<script setup>
import { useAccount } from 'dashboard/composables/useAccount';

// Reports pick their days in the account's reports timezone, so they wait for the account to load
const { currentAccount } = useAccount();
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-5xl mx-auto pb-12">
      <router-view v-if="currentAccount.id" />
    </div>
  </div>
</template>
