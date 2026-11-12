// The words of the activity feed: one entry per event, from its kind and its data. Everything here is plain text that
// the template interpolates, never markup: titles, comments and names are untrusted.

var TITLE_MAX = 60;
var EXCERPT_MAX = 80;
var MINUTE = 60000;
var HOUR = 60 * MINUTE;

// What each kind says after the actor, and its group, which gives its mark and color and is what the filter picks.
// A kind of card names the card after the verb; a kind of column or board names the column or board instead.
var KINDS = {
  "card.created": { verb: "created", group: "create" },
  "card.updated": { verb: "updated", group: "update" },
  "card.claimed": { verb: "claimed", group: "claim" },
  "card.released": { verb: "released", group: "release" },
  "card.moved": { verb: "moved", group: "move" },
  "card.done": { verb: "closed", group: "done" },
  "comment.added": { verb: "commented on", group: "comment" },
  "dep.added": { verb: "added a dependency to", group: "dep" },
  "dep.removed": { verb: "removed a dependency from", group: "dep" },
  "column.added": { verb: "added the column", group: "board" },
  "column.updated": { verb: "changed the column", group: "board" },
  "column.removed": { verb: "removed the column", group: "board" },
  "board.created": { verb: "created the board", group: "board" },
};

// The groups in the order of the filter, with their names there.
export var GROUPS = [
  ["move", "Moves"],
  ["done", "Closed"],
  ["comment", "Comments"],
  ["claim", "Claims"],
  ["release", "Releases"],
  ["create", "New cards"],
  ["update", "Updates"],
  ["dep", "Dependencies"],
  ["board", "Columns and board"],
  ["other", "Other"],
];

// The grapheme segmenter keeps a family emoji or a letter with its accents whole at the cut; where it is missing the
// text splits by code point, which is the best that `Array.from` gives.
var segmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter("und", { granularity: "grapheme" }) : null;

function characters(text) {
  return segmenter ? Array.from(segmenter.segment(text), function (part) { return part.segment; }) : Array.from(text);
}

// `text` on one line, cut to `max` characters (whole ones: no half of a surrogate pair, no ZWJ fragment) with an ellipsis.
export function cut(text, max) {
  var flat = String(text).replace(/\s+/g, " ").trim();
  // A text of `max` units or fewer has at most `max` characters, so it needs no segmenting. A longer one (a comment or a
  // column name can have thousands of characters) is segmented only up to eight units a character, and in full when
  // that prefix has too few characters to tell (a text of long ZWJ sequences).
  if (flat.length <= max) {
    return flat;
  }
  var chars = characters(flat.length > max * 8 ? flat.slice(0, max * 8) : flat);
  if (chars.length <= max && flat.length > max * 8) {
    chars = characters(flat);
  }
  return chars.length > max ? chars.slice(0, max - 1).join("").trimEnd() + "…" : flat;
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {};
}

// The card of an event: `data.card` for a move, a release or a close; the data itself for the other card kinds.
function cardOf(event) {
  var data = object(event.data);
  return data.card ? object(data.card) : data;
}

// One entry of the feed. `titles` maps the card ids of the board to their titles, for the kinds whose data has no card
// (a comment) and for a card retitled since; the title in the event data is the fallback (a card archived since).
// `to` and `from` are column names; `from` is missing in events older than it, and then only `to` shows.
export function entry(event, titles) {
  var known = KINDS[event.kind];
  var data = object(event.data);
  var card = event.card_id === null || event.card_id === undefined ? null : event.card_id;
  var result = {
    id: event.id,
    actor: event.actor,
    group: known ? known.group : "other",
    verb: known ? known.verb : event.kind,
    card: card,
    title: "",
    name: "",
    from: "",
    to: "",
    toDone: false,
    reordered: false,
    excerpt: "",
    // Every event has its time; a malformed one shows as now rather than breaking the feed.
    at: Number.isFinite(event.created_at) ? event.created_at : Date.now(),
  };

  if (card !== null) {
    var title = titles[card] !== undefined ? titles[card] : cardOf(event).title;
    result.title = typeof title === "string" ? cut(title, TITLE_MAX) : "";
  }

  if (event.kind === "card.moved" || event.kind === "card.done" || event.kind === "card.released") {
    var moved = object(data.card);
    var from = object(data.from);
    result.to = typeof moved.column === "string" ? cut(moved.column, TITLE_MAX) : "";
    result.toDone = moved.done === true;
    result.from = typeof from.name === "string" ? cut(from.name, TITLE_MAX) : "";
    // A release that keeps the card in its column has no from and to. A move inside one column is a reorder: it names
    // that column once.
    if (from.id !== undefined && from.id === moved.column_id) {
      result.from = "";
      if (event.kind === "card.moved") {
        result.reordered = true;
        result.verb = "reordered";
      } else {
        result.to = "";
      }
    }
  } else if (event.kind === "comment.added") {
    result.excerpt = typeof data.body === "string" ? cut(data.body, EXCERPT_MAX) : "";
  } else if (result.group === "board") {
    result.name = typeof data.name === "string" ? cut(data.name, TITLE_MAX) : "";
  }

  return result;
}

function startOfDay(ms) {
  var day = new Date(ms);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

// "just now", "5 min ago", "3 h ago"; from a day back, the time of day (the day separator gives the date).
export function relative(ms, now) {
  var ago = now - ms;
  if (ago < MINUTE) {
    return "just now";
  }
  if (ago < HOUR) {
    return Math.floor(ago / MINUTE) + " min ago";
  }
  if (ago < 24 * HOUR) {
    return Math.floor(ago / HOUR) + " h ago";
  }
  return new Date(ms).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

// The separator of the day of `ms`: "Today", "Yesterday" or the date.
export function day(ms, now) {
  var today = startOfDay(now);
  var start = startOfDay(ms);
  if (start === today) {
    return "Today";
  }
  if (start === startOfDay(today - 1)) {
    return "Yesterday";
  }
  var options = { weekday: "short", day: "numeric", month: "short" };
  if (new Date(ms).getFullYear() !== new Date(now).getFullYear()) {
    options.year = "numeric";
  }
  return new Date(ms).toLocaleDateString(undefined, options);
}

// The entries by day, newest first, as the feed lists them: [{ key, label, entries }].
export function byDay(entries, now) {
  var days = [];
  entries.forEach(function (one) {
    var key = startOfDay(one.at);
    var last = days[days.length - 1];
    if (!last || last.key !== key) {
      last = { key: key, label: day(one.at, now), entries: [] };
      days.push(last);
    }
    last.entries.push(one);
  });
  return days;
}
