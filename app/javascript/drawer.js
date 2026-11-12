import { ref } from "vue";

var KEY = "agc-kanban.drawer";
export var NARROW = "(max-width: 700px)"; // the same width as $narrow of the stylesheet

function saved() {
  try {
    return localStorage.getItem(KEY);
  } catch (error) {
    return null;
  }
}

function save(name) {
  try {
    localStorage.setItem(KEY, name);
  } catch (error) {
    // No storage (a private window): the choice lasts until the reload.
  }
}

// The right-side drawer of the board page. It shows one panel at a time, by name ("activity" is the feed; the card
// detail will be another), and `panel` is "" while it is closed. The choice is kept in localStorage; with nothing kept,
// the activity is open, except on a narrow screen, where the drawer would cover the board.
export function useDrawer() {
  var first = saved();
  var panel = ref(first !== null ? first : (matchMedia(NARROW).matches ? "" : "activity"));

  function show(name) {
    panel.value = name;
    save(name);
  }

  return {
    panel: panel,
    show: show,
    close: function () { show(""); },
    toggle: function (name) { show(panel.value === name ? "" : name); },
  };
}
