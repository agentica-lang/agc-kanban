import { computed, ref } from "vue";

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

  function showCard(id) {
    if (id !== null) {
      filters.value = false;
    }
    card.value = id;
    var url = new URL(location.href);
    if (id === null) {
      url.searchParams.delete("card");
    } else {
      url.searchParams.set("card", id);
    }
    history.replaceState(history.state, "", url);
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
