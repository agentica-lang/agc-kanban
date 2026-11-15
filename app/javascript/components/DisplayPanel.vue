<script setup>
import { OPTIONS } from "../display.js";

// What a card shows, in the drawer of the gear button. Each choice is a checkbox, so the keyboard and a screen reader
// have them as they are; the choice shows at once and is kept in this browser, per board (display.js).
defineProps({ store: Object });
</script>

<template>
  <div class="display-panel">
    <fieldset>
      <legend>Show on the cards</legend>
      <label v-for="option in OPTIONS" :key="option.key" class="display-option">
        <input type="checkbox" :checked="store.settings[option.key]" @change="store.set(option.key, $event.target.checked)" />
        <span class="display-name">{{ option.label }}</span>
        <span v-if="option.hint" class="display-hint">{{ option.hint }}</span>
      </label>
    </fieldset>
    <button type="button" class="display-reset" :disabled="store.isDefault()" @click="store.reset()">Reset to defaults</button>
    <p class="display-note">Kept in this browser, for this board.</p>
  </div>
</template>
