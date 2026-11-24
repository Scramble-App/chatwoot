// jsdom has no showModal, so specs swap the components-next Dialog for this stub
export const DialogStub = {
  name: 'Dialog',
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
    confirmButtonLabel: { type: String, default: '' },
    disableConfirmButton: { type: Boolean, default: false },
    isLoading: { type: Boolean, default: false },
  },
  emits: ['confirm', 'close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
      this.$emit('close');
    },
  },
  template: `
    <div v-if="isOpen" class="dialog-stub">
      <h3 class="dialog-title">{{ title }}</h3>
      <p>{{ description }}</p>
      <slot />
      <button
        class="dialog-confirm"
        :disabled="disableConfirmButton || isLoading"
        @click="$emit('confirm')"
      >
        {{ confirmButtonLabel }}
      </button>
    </div>
  `,
};
