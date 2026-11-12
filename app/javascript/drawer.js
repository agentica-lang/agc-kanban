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

// The right-side drawer of the board page shows one panel at a time: `panel` is "activity" (the feed), "card" (the
// detail of `card`) or "" while it is closed. Only the activity choice is kept in localStorage; with nothing kept, it
// is closed. The open card is in the URL, so a reload or a shared link opens it again; closing it shows the activity
// again when that was open.
export function useDrawer() {
  var activity = ref(saved() === "activity");
  var card = ref(cardInUrl());
  var panel = computed(function () {
    if (card.value !== null) {
      return "card";
    }
    return activity.value ? "activity" : "";
  });

  function showCard(id) {
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
        showActivity(true);
      }
    },
    close: function () {
      if (card.value !== null) {
        showCard(null);
      } else {
        showActivity(false);
      }
    },
  };
}
