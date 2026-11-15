import { reactive } from "vue";
import { cut } from "./feed.js";

var PREFIX = "agc-kanban.display.";

// What a card of the board shows. The first value of each is the default: everything a card shows today, and the
// relation chips; the lines between related cards, the links, the time in the column and the preview of the body are
// off until the viewer asks.
export var OPTIONS = [
  { key: "relations", label: "Relations", hint: "Chips for the cards it depends on and the cards it blocks; hover or focus a card to mark its related cards", on: true },
  { key: "lines", label: "Relation lines", hint: "Lines between related cards", on: false },
  { key: "labels", label: "Labels", hint: "", on: true },
  { key: "agent", label: "Claimed by", hint: "The agent that holds the card", on: true },
  { key: "links", label: "Links", hint: "Pull requests, issues and other links", on: false },
  { key: "time", label: "Time in column", hint: "How long the card has been in its column", on: false },
  { key: "body", label: "Body preview", hint: "The first line of the body", on: false },
];

export var DEFAULTS = Object.fromEntries(OPTIONS.map(function (option) { return [option.key, option.on]; }));

function storage() {
  try {
    return globalThis.localStorage || null;
  } catch (error) {
    return null;
  }
}

// The settings of a board as `writeDisplay` keeps them. Each one that is not stored as a boolean has its default, so a
// broken value, a name this version does not know and a missing key never change what shows.
export function readDisplay(store, slug) {
  var kept = {};
  try {
    var parsed = JSON.parse(store.getItem(PREFIX + slug));
    kept = parsed !== null && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch (error) {
    kept = {};
  }
  var settings = {};
  Object.keys(DEFAULTS).forEach(function (key) {
    settings[key] = typeof kept[key] === "boolean" ? kept[key] : DEFAULTS[key];
  });
  return settings;
}

// Only what differs from the defaults is kept, so a new default reaches a viewer who never changed that setting.
export function writeDisplay(store, slug, settings) {
  var changed = {};
  Object.keys(DEFAULTS).forEach(function (key) {
    if (settings[key] !== DEFAULTS[key]) {
      changed[key] = settings[key];
    }
  });
  try {
    if (Object.keys(changed).length) {
      store.setItem(PREFIX + slug, JSON.stringify(changed));
    } else {
      store.removeItem(PREFIX + slug);
    }
  } catch (error) {
    // No storage (a private window): the settings stay as they are until the reload.
  }
}

// The display settings of the board page, per viewer and per board: kept in this browser only, as the collapsed columns.
export function useDisplay(slug) {
  var settings = reactive(readDisplay(storage(), slug));

  function save() {
    writeDisplay(storage(), slug, settings);
  }

  return {
    settings: settings,
    set: function (key, value) {
      if (key in DEFAULTS) {
        settings[key] = Boolean(value);
        save();
      }
    },
    reset: function () {
      Object.assign(settings, DEFAULTS);
      save();
    },
    isDefault: function () {
      return Object.keys(DEFAULTS).every(function (key) { return settings[key] === DEFAULTS[key]; });
    },
  };
}

var PREVIEW_MAX = 120;

// The first line of a body that says something, with the Markdown marks of a heading, a quote, a list item, code and a
// link taken off: the text of a card for a short line under its title.
export function preview(body) {
  var lines = String(body || "").split("\n");
  for (var i = 0; i < lines.length; i += 1) {
    var text = lines[i]
      .replace(/^\s*(#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)/, "")
      .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/[`*_~]/g, "")
      .trim();
    if (text && !/^[-=]{3,}$/.test(text) && !/^```/.test(lines[i].trim())) {
      return cut(text, PREVIEW_MAX);
    }
  }
  return "";
}
