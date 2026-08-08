<template>
  <BaseDialog :trigger-class="triggerClass">
    <template #trigger><slot /></template>
    <template #title>{{ $t('awg.presetTitle') }}</template>
    <template #description>
      <div class="flex flex-col gap-3 py-2 text-left">
        <p class="text-xs text-gray-600 dark:text-neutral-300">
          {{ $t('awg.presetDescription') }}
        </p>

        <div class="flex flex-col gap-2">
          <label
            v-for="preset in presets"
            :key="preset.id"
            :class="[
              'cursor-pointer rounded border p-3 transition',
              selectedPresetId === preset.id
                ? 'border-red-800 bg-red-50 dark:border-red-600 dark:bg-neutral-700'
                : 'border-gray-300 hover:border-gray-400 dark:border-neutral-600 dark:hover:border-neutral-500'
            ]"
            @click="selectedPresetId = preset.id"
          >
            <div class="flex items-center gap-2">
              <input
                type="radio"
                :name="'awg-preset'"
                :value="preset.id"
                :checked="selectedPresetId === preset.id"
                class="accent-red-800"
              />
              <span class="font-medium text-sm text-gray-900 dark:text-white">
                {{ preset.title }}
              </span>
            </div>
            <p class="mt-1 pl-5 text-xs text-gray-500 dark:text-neutral-400">
              {{ preset.desc }}
            </p>
          </label>
        </div>

        <label
          v-if="!clientMode"
          class="mt-2 flex cursor-pointer items-center gap-2 rounded border border-gray-200 p-2.5 transition hover:border-gray-300 dark:border-neutral-700 dark:hover:border-neutral-600"
        >
          <input
            v-model="randomizeHeaders"
            type="checkbox"
            class="size-4 rounded accent-red-800"
          />
          <span class="text-xs font-medium text-gray-700 dark:text-neutral-300">
            {{ $t('awg.randomizeHeadersOnPreset') }}
          </span>
        </label>
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
      <DialogClose as-child>
        <BasePrimaryButton @click="applyPreset">
          {{ $t('awg.applyPreset') }}
        </BasePrimaryButton>
      </DialogClose>
    </template>
  </BaseDialog>
</template>

<script lang="ts" setup>
const emit = defineEmits<{
  (e: 'apply', values: Record<string, any>): void;
}>();

const props = withDefaults(
  defineProps<{
    triggerClass?: string;
    clientMode?: boolean;
  }>(),
  {
    clientMode: false,
  }
);

const { t } = useI18n();

const selectedPresetId = ref('dns');
const randomizeHeaders = ref(true);

const presets = computed(() => [
  {
    id: 'dns',
    title: t('awg.presets.dnsTitle'),
    desc: t('awg.presets.dnsDesc'),
    values: {
      jC: 4,
      jMin: 40,
      jMax: 120,
      s1: 128,
      s2: 56,
      s3: 100,
      s4: 200,
      i1: '<b 0x1a2b01000001000000000000076578616d706c6503636f6d0000010001>',
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    },
  },
  {
    id: 'quic',
    title: t('awg.presets.quicTitle'),
    desc: t('awg.presets.quicDesc'),
    values: {
      jC: 5,
      jMin: 100,
      jMax: 800,
      s1: 140,
      s2: 64,
      s3: 120,
      s4: 240,
      i1: '<b 0xc000000001><r 20><b 0x00><r 64>',
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    },
  },
  {
    id: 'stun',
    title: t('awg.presets.stunTitle'),
    desc: t('awg.presets.stunDesc'),
    values: {
      jC: 4,
      jMin: 20,
      jMax: 100,
      s1: 80,
      s2: 40,
      s3: 60,
      s4: 120,
      i1: '<b 0x000100002112a442><r 12>',
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    },
  },
  {
    id: 'standard',
    title: t('awg.presets.standardTitle'),
    desc: t('awg.presets.standardDesc'),
    values: {
      jC: 7,
      jMin: 10,
      jMax: 1000,
      s1: 128,
      s2: 56,
      s3: 100,
      s4: 200,
      i1: null,
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    },
  },
  {
    id: 'clean',
    title: t('awg.presets.cleanTitle'),
    desc: t('awg.presets.cleanDesc'),
    values: {
      jC: null,
      jMin: null,
      jMax: null,
      s1: null,
      s2: null,
      s3: null,
      s4: null,
      h1: null,
      h2: null,
      h3: null,
      h4: null,
      i1: null,
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    },
  },
]);

function generateRandomHeaderRanges(): {
  h1: string;
  h2: string;
  h3: string;
  h4: string;
} {
  const bandSize = Math.floor(4000000000 / 4);
  const ranges: string[] = [];
  for (let slot = 0; slot < 4; slot++) {
    const bandStart = 10000000 + slot * bandSize;
    const start = bandStart + Math.floor(Math.random() * (bandSize / 2));
    const span = Math.floor(Math.random() * 500000) + 50000;
    ranges.push(`${start}-${start + span}`);
  }
  return {
    h1: ranges[0]!,
    h2: ranges[1]!,
    h3: ranges[2]!,
    h4: ranges[3]!,
  };
}

function applyPreset() {
  const preset = presets.value.find((p) => p.id === selectedPresetId.value);
  if (preset) {
    if (props.clientMode || preset.id === 'clean' || !randomizeHeaders.value) {
      emit('apply', preset.values);
    } else {
      const ranges = generateRandomHeaderRanges();
      emit('apply', {
        ...ranges,
        ...preset.values,
      });
    }
  }
}
</script>
