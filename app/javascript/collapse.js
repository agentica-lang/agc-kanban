import { ref } from "vue";

var PREFIX = "agc-kanban.collapsed.";

function storage() {
  try {
    return globalThis.localStorage || null;
  } catch (error) {
    return null;
  }
}

// The ids of the collapsed columns of a board, as `writeCollapsed` keeps them; [] when nothing (or nothing readable) is
// kept, or when there is no storage.
export function readCollapsed(store, slug) {
  try {
    var ids = JSON.parse(store.getItem(PREFIX + slug));
    return Array.isArray(ids) ? ids.filter(Number.isInteger) : [];
  } catch (error) {
    return [];
  }
}

export function writeCollapsed(store, slug, ids) {
  try {
    if (ids.length) {
      store.setItem(PREFIX + slug, JSON.stringify(ids));
    } else {
      store.removeItem(PREFIX + slug);
    }
  } catch (error) {
    // No storage (a private window): the columns stay as they are until the reload.
  }
}

// The collapsed columns of the board page, per viewer and per board: kept in this browser only, never on the server.
// Kept by column id, so a renamed column stays collapsed and a live refresh of the board does not open it.
export function useCollapsed(slug) {
  var ids = ref(readCollapsed(storage(), slug));

  function set(next) {
    ids.value = next;
    writeCollapsed(storage(), slug, next);
  }

  return {
    ids: function () { return ids.value; },
    has: function (id) { return ids.value.includes(id); },
    toggle: function (id) {
      set(ids.value.includes(id) ? ids.value.filter(function (one) { return one !== id; }) : ids.value.concat([id]));
    },
    // The database gives the id of a deleted column to the next new one, so the ids of the columns the board no longer
    // has are dropped as soon as the page sees them go. A column deleted and another added while the page was closed
    // still cannot be told apart: the new one shows collapsed.
    keep: function (columnIds) {
      var next = ids.value.filter(function (id) { return columnIds.includes(id); });
      if (next.length !== ids.value.length) {
        set(next);
      }
    },
  };
}
