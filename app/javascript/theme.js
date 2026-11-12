import { onBeforeUnmount, ref } from "vue";

// The same key as the inline script of the layout (src/kanban_web/views.agc), which applies the saved theme before
// the first paint.
var KEY = "agc-kanban.theme";

function save(theme) {
  try {
    localStorage.setItem(KEY, theme);
  } catch (error) {
    // No storage (a private window): the choice lasts until the reload.
  }
}

// The light/dark theme. With nothing saved (or a value that is neither "light" nor "dark") it follows the system
// setting; a toggle sets `data-theme` on <html> and saves it, and from then on the choice wins over the system.
// `theme` is the theme on screen, kept current when the system setting changes.
export function useTheme() {
  var root = document.documentElement;
  var system = window.matchMedia("(prefers-color-scheme: dark)");

  function current() {
    var chosen = root.dataset.theme;
    if (chosen === "light" || chosen === "dark") {
      return chosen;
    }
    return system.matches ? "dark" : "light";
  }

  var theme = ref(current());
  function follow() { theme.value = current(); }
  system.addEventListener("change", follow);
  onBeforeUnmount(function () { system.removeEventListener("change", follow); });

  return {
    theme: theme,
    toggle: function () {
      var next = theme.value === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      save(next);
      theme.value = next;
    },
  };
}
