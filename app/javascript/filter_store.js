import { getCurrentScope, onScopeDispose, ref } from "vue";
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

  // Back and Forward land on an entry whose URL may be older than the filters (they are written to the entry that was
  // current when they changed): the filters stay as they are, and the URL takes them back.
  function onPopState() {
    var inUrl = parse(location.search);
    if (JSON.stringify(inUrl) === JSON.stringify(filters.value)) {
      return;
    }
    var url = new URL(location.href);
    url.search = search(location.search, filters.value);
    history.replaceState(history.state, "", url);
  }
  window.addEventListener("popstate", onPopState);
  if (getCurrentScope()) {
    onScopeDispose(function () { window.removeEventListener("popstate", onPopState); });
  }

  return {
    filters: filters,
    label: function (name) { set(toggleLabel(filters.value, name)); },
    claimer: function (name) { set(toggleClaimer(filters.value, name)); },
    ready: function () { set(toggleReady(filters.value)); },
    clear: function () { set(NO_FILTERS); },
  };
}
