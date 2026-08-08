<template>
  <BaseDialog :trigger-class="triggerClass">
    <template #trigger><slot /></template>
    <template #title>{{ $t('awg.mtuDialog.title') }}</template>
    <template #description>
      <div class="flex flex-col gap-3 py-2 text-left">
        <p class="text-xs text-gray-600 dark:text-neutral-300">
          {{ $t('awg.mtuDialog.description') }}
        </p>

        <!-- Target host test input -->
        <div
          class="flex items-center gap-2 rounded border border-gray-200 p-2.5 dark:border-neutral-700"
        >
          <input
            v-model.trim="customTarget"
            type="text"
            placeholder="1.1.1.1"
            class="w-full rounded border border-gray-300 bg-white px-2.5 py-1 text-xs text-gray-900 focus:border-red-800 focus:outline-none dark:border-neutral-600 dark:bg-neutral-800 dark:text-white"
            @keyup.enter="measureMtu"
          />
          <BasePrimaryButton
            type="button"
            class="whitespace-nowrap px-3 py-1 text-xs"
            :disabled="pending"
            @click="measureMtu"
          >
            <span v-if="pending">{{ $t('general.loading') }}</span>
            <span v-else>{{ $t('awg.mtuDialog.testTarget') }}</span>
          </BasePrimaryButton>
        </div>

        <!-- Diagnostic summary banner -->
        <div
          v-if="mtuData"
          class="rounded border border-blue-200 bg-blue-50 p-2.5 text-xs text-blue-900 dark:border-blue-900/40 dark:bg-neutral-800 dark:text-blue-200"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium">
              {{ $t('awg.mtuDialog.detectedPmtu') }}:
              <strong class="font-bold text-red-800 dark:text-red-400">
                {{ mtuData.detectedPmtu }} B
              </strong>
            </span>
            <span class="text-gray-500 dark:text-neutral-400">
              {{ mtuData.interfaceName }}: {{ mtuData.interfaceMtu }} B
            </span>
          </div>
          <p class="mt-1 text-[11px] text-gray-600 dark:text-neutral-400">
            {{ $t('awg.mtuDialog.testedAgainst') }}: {{ mtuData.testedTarget }}
            <span
              v-if="mtuData.isMeasured"
              class="font-medium text-green-600 dark:text-green-400"
            >
              ({{ $t('awg.mtuDialog.measuredSuccess') }})
            </span>
          </p>
        </div>

        <!-- Presets and Recommendations -->
        <div class="flex max-h-60 flex-col gap-2 overflow-y-auto pr-1">
          <label
            v-for="preset in presetOptions"
            :key="preset.id"
            :class="[
              'cursor-pointer rounded border p-2.5 transition',
              selectedMtu === preset.value
                ? 'border-red-800 bg-red-50 dark:border-red-600 dark:bg-neutral-700'
                : 'border-gray-300 hover:border-gray-400 dark:border-neutral-600 dark:hover:border-neutral-500',
            ]"
            @click="selectedMtu = preset.value"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <input
                  type="radio"
                  name="mtu-preset"
                  :value="preset.value"
                  :checked="selectedMtu === preset.value"
                  class="accent-red-800"
                />
                <span
                  class="text-xs font-semibold text-gray-900 dark:text-white"
                >
                  {{ preset.value }} — {{ $t(preset.title) }}
                </span>
              </div>
              <span
                v-if="preset.badge"
                class="rounded bg-gray-200 px-1.5 py-0.5 text-[10px] font-medium text-gray-700 dark:bg-neutral-600 dark:text-neutral-200"
              >
                {{ preset.badge }}
              </span>
            </div>
            <p
              class="mt-1 pl-5 text-[11px] text-gray-500 dark:text-neutral-400"
            >
              {{ $t(preset.desc) }}
            </p>
          </label>

          <!-- Custom MTU Option -->
          <label
            :class="[
              'cursor-pointer rounded border p-2.5 transition',
              isCustomSelected
                ? 'border-red-800 bg-red-50 dark:border-red-600 dark:bg-neutral-700'
                : 'border-gray-300 hover:border-gray-400 dark:border-neutral-600 dark:hover:border-neutral-500',
            ]"
            @click="selectCustom"
          >
            <div class="flex items-center gap-2">
              <input
                type="radio"
                name="mtu-preset"
                value="custom"
                :checked="isCustomSelected"
                class="accent-red-800"
              />
              <span class="text-xs font-semibold text-gray-900 dark:text-white">
                {{ $t('awg.mtuDialog.customTitle') }}
              </span>
            </div>
            <div v-if="isCustomSelected" class="mt-2 pl-5">
              <input
                v-model.number="customMtuInput"
                type="number"
                min="1280"
                max="9000"
                class="w-32 rounded border border-gray-300 bg-white px-2 py-1 text-xs text-gray-900 focus:border-red-800 focus:outline-none dark:border-neutral-600 dark:bg-neutral-800 dark:text-white"
                @input="selectedMtu = customMtuInput"
              />
            </div>
          </label>
        </div>
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
      <DialogClose as-child>
        <BasePrimaryButton @click="applyMtu">
          {{ $t('awg.mtuDialog.apply') }}
        </BasePrimaryButton>
      </DialogClose>
    </template>
  </BaseDialog>
</template>

<script lang="ts" setup>
import type { MtuCalculation } from '#server/utils/mtu';

const emit = defineEmits<{
  (e: 'apply', value: number): void;
}>();

const props = withDefaults(
  defineProps<{
    triggerClass?: string;
    currentMtu?: number;
  }>(),
  {
    triggerClass: '',
    currentMtu: 1420,
  }
);

const customTarget = ref('1.1.1.1');
const selectedMtu = ref(props.currentMtu || 1420);
const customMtuInput = ref(props.currentMtu || 1420);
const isCustomSelected = ref(false);

const {
  data: mtuData,
  pending,
  refresh,
} = await useFetch<MtuCalculation>('/api/admin/mtu-info', {
  method: 'get',
  query: computed(() => ({ target: customTarget.value })),
});

const presetOptions = computed(() => {
  if (mtuData.value?.presets) {
    return mtuData.value.presets;
  }
  return [
    {
      id: 'awg-recommended',
      value: 1420,
      title: 'awg.mtuDialog.presetAwgTitle',
      desc: 'awg.mtuDialog.presetAwgDesc',
      badge: 'AWG 3.0',
    },
    {
      id: 'wg-ipv4',
      value: 1440,
      title: 'awg.mtuDialog.presetWgIpv4Title',
      desc: 'awg.mtuDialog.presetWgIpv4Desc',
      badge: 'WireGuard IPv4',
    },
    {
      id: 'double-tunnel',
      value: 1360,
      title: 'awg.mtuDialog.presetDoubleTunnelTitle',
      desc: 'awg.mtuDialog.presetDoubleTunnelDesc',
      badge: 'Safe / Double Tunnel',
    },
    {
      id: 'mobile-roaming',
      value: 1280,
      title: 'awg.mtuDialog.presetMobileTitle',
      desc: 'awg.mtuDialog.presetMobileDesc',
      badge: 'LTE / Roaming',
    },
  ];
});

watch(
  () => mtuData.value,
  (newData) => {
    if (newData?.recommendations?.awgRecommended && !props.currentMtu) {
      selectedMtu.value = newData.recommendations.awgRecommended;
    }
  }
);

function selectCustom() {
  isCustomSelected.value = true;
  selectedMtu.value = customMtuInput.value;
}

watch(
  () => selectedMtu.value,
  (val) => {
    const isPreset = presetOptions.value.some((p) => p.value === val);
    if (!isPreset) {
      isCustomSelected.value = true;
      customMtuInput.value = val;
    } else {
      isCustomSelected.value = false;
    }
  }
);

async function measureMtu() {
  await refresh();
  if (mtuData.value?.recommendations?.awgRecommended) {
    selectedMtu.value = mtuData.value.recommendations.awgRecommended;
  }
}

function applyMtu() {
  const finalMtu = isCustomSelected.value
    ? customMtuInput.value
    : selectedMtu.value;
  if (finalMtu && finalMtu >= 1280 && finalMtu <= 9000) {
    emit('apply', finalMtu);
  }
}
</script>
