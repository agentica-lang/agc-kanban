import { ref } from "vue";
import { NO_FILTERS, parse, search, toggleClaimer, toggleLabel, toggleReady } from "./filters.js";

// The filters of the board page, read from the URL when the page opens and written back (without a history entry, as the
// open card is) at each change, so a reload or a shared link shows the same view.
export function useFilters() {
  var filters = ref(parse(location.search));

  function set(next) {
    filters.value = next;
    var url = new URL(location.href);
    url.search = search(location.search, next);
    history.replaceState(history.state, "", url);
  }

  return {
    filters: filters,
    label: function (name) { set(toggleLabel(filters.value, name)); },
    claimer: function (name) { set(toggleClaimer(filters.value, name)); },
    ready: function () { set(toggleReady(filters.value)); },
    clear: function () { set(NO_FILTERS); },
  };
}
