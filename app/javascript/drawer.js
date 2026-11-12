import { computed, getCurrentScope, onScopeDispose, ref } from "vue";

var KEY = "agc-kanban.drawer";

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

// Whether a click is a plain one on a link: the left button and no modifier. A click with a modifier (or the middle
// button, which sends no click at all) is left to the browser, so a link opens in a new tab or window.
export function plainClick(event) {
  return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

// The open card of the URL (`?card=12`), or null.
function cardInUrl() {
  var id = Number(new URLSearchParams(location.search).get("card"));
  return Number.isInteger(id) && id > 0 ? id : null;
}

// The right-side drawer of the board page shows one panel at a time: `panel` is "filters" (the filter choices), "card"
// (the detail of `card`), "activity" (the feed) or "" while it is closed. Only the activity choice is kept in
// localStorage; with nothing kept, it is closed. The open card is in the URL, so a reload or a shared link opens it
// again. Closing the card or the filters shows the activity again when that was open; opening a card closes the
// filters.
export function useDrawer() {
  var activity = ref(saved() === "activity");
  var card = ref(cardInUrl());
  var filters = ref(false);
  var panel = computed(function () {
    if (card.value !== null) {
      return "card";
    }
    if (filters.value) {
      return "filters";
    }
    return activity.value ? "activity" : "";
  });

  // Opening or closing a card is a step in the history, so Back goes to the card shown before, then to the board; the
  // URL keeps what else it holds (the filters). Showing what is shown already adds no entry.
  function showCard(id) {
    if (id !== null) {
      filters.value = false;
    }
    if (id === card.value) {
      return;
    }
    card.value = id;
    var url = new URL(location.href);
    if (id === null) {
      url.searchParams.delete("card");
    } else {
      url.searchParams.set("card", id);
    }
    history.pushState(null, "", url);
  }

  // Back and Forward change the URL without a click: the panel follows its `?card=`. The filters are view state that
  // the page keeps in memory, so they do not come from the entry (an entry made before a filter was set has none).
  function onPopState() {
    card.value = cardInUrl();
    if (card.value !== null) {
      filters.value = false;
    }
  }
  window.addEventListener("popstate", onPopState);
  if (getCurrentScope()) {
    onScopeDispose(function () { window.removeEventListener("popstate", onPopState); });
  }

  function showActivity(open) {
    activity.value = open;
    save(open ? "activity" : "");
  }

  return {
    panel: panel,
    card: card,
    showCard: showCard,
    toggleActivity: function () {
      if (panel.value === "activity") {
        showActivity(false);
      } else {
        showCard(null);
        filters.value = false;
        showActivity(true);
      }
    },
    toggleFilters: function () {
      if (panel.value === "filters") {
        filters.value = false;
      } else {
        showCard(null);
        filters.value = true;
      }
    },
    close: function () {
      if (card.value !== null) {
        showCard(null);
      } else if (filters.value) {
        filters.value = false;
      } else {
        showActivity(false);
      }
    },
  };
}
