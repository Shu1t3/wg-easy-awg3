<template>
  <div class="flex items-center">
    <FormLabel :for="id">
      {{ label }}
    </FormLabel>
    <BaseTooltip v-if="description" :text="description">
      <IconsInfo class="size-4" />
    </BaseTooltip>
  </div>
  <div class="flex gap-1">
    <BaseInput
      :id="id"
      v-model.number="data"
      :name="id"
      type="number"
      min="1280"
      max="9000"
      class="w-full"
      :placeholder="placeholder"
    />
    <ClientOnly>
      <AdminMtuDialog :current-mtu="data ?? 1420" @apply="data = $event">
        <BasePrimaryButton as="span" class="cursor-pointer">
          <div class="flex items-center gap-2">
            <IconsSparkles class="size-4" />
            <span class="whitespace-nowrap">
              {{ $t('awg.mtuDialog.button') }}
            </span>
          </div>
        </BasePrimaryButton>
      </AdminMtuDialog>
    </ClientOnly>
  </div>
</template>

<script lang="ts" setup>
defineProps<{
  id: string;
  label: string;
  description?: string;
  placeholder?: string;
}>();

const data = defineModel<number>();
</script>
