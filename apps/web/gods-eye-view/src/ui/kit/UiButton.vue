<!--
 Copyright (c) 2026 VitruvianSoftware

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
-->

<script setup>
import { computed } from 'vue';
import { vClassToggle } from '../rail/classToggle.js';

// Core's button and its attribute contract: the button is always the root,
// attributes passed in win over its own (a `title` replaces the label's), and
// `pressed` renders aria-pressed only when it is passed. Core styles the
// button through the classes its callers pass; the kit classes carry no Core
// styles yet. Core adds `pressedClass`, its class on a pressed button (most
// toggles use `active`). The pressed classes toggle through `classList`, so
// classes other code adds to the button (a voice highlight) survive a press.
// Not mirrored yet: icon, loading, disabledReason and the missing-label
// warning.
defineOptions({ inheritAttrs: false });

const props = defineProps({
  variant: { type: String, default: 'ghost' },
  tone: { type: String, default: 'accent' },
  /** The accessible name (aria-label) and, with nativeTitle, the tip. */
  label: { type: String, default: undefined },
  pressed: { type: Boolean, default: undefined },
  /** Core's class on the button while it is pressed. */
  pressedClass: { type: String, default: undefined },
  disabled: { type: Boolean, default: false },
  type: { type: String, default: 'button' },
  /** The id of the form a submit button belongs to, where it sits outside it. */
  form: { type: String, default: undefined },
  nativeTitle: { type: Boolean, default: true },
});
const emit = defineEmits(['click']);

// A pressedClass that changes keeps its old name, switched off, so the class
// leaves the button with it.
const pressedClasses = computed((previous) => {
  const on = Boolean(props.pressed);
  const classes = { 'ui-button--pressed': on };
  for (const name of Object.keys(previous || {}))
    if (name !== 'ui-button--pressed') classes[name] = false;
  if (props.pressedClass) classes[props.pressedClass] = on;
  return classes;
});
// Server-rendered markup carries the pressed classes in its class attribute.
const vPressedClasses = {
  ...vClassToggle,
  getSSRProps: ({ value }) => ({
    class: Object.keys(value).filter((name) => value[name]),
  }),
};
</script>

<template>
  <button
    :type="props.type"
    :form="props.form"
    class="ui-button ui-focus"
    :class="[`ui-button--${props.variant}`, `ui-button--${props.tone}`]"
    :aria-label="props.label"
    :title="props.nativeTitle ? props.label : undefined"
    :aria-pressed="
      props.pressed === undefined ? undefined : props.pressed ? 'true' : 'false'
    "
    :disabled="props.disabled"
    v-bind="$attrs"
    v-pressed-classes="pressedClasses"
    @click="emit('click', $event)"
  >
    <slot />
  </button>
</template>
