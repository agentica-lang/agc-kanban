// The filters of the board view: labels (a card shows only with all of them), the agent holding the card, and ready
// only. They are view state: they live in the URL (`?label=cc,0.8.0&claimer=line1&ready=1`, next to `?card=`), so a
// link keeps them, and they are applied in the browser to the cards already loaded. The server is never asked.

var LABEL = "label";
var CLAIMER = "claimer";
var READY = "ready";

// Labels are joined with a comma in the URL, so a label that has one cannot be selected (the CLI cannot make one either).
export function selectable(label) {
  return typeof label === "string" && label !== "" && label.indexOf(",") === -1;
}

function unique(list) {
  return list.filter(function (item, index) { return item !== "" && list.indexOf(item) === index; });
}

// The filters of a query string: `{ labels: [...], claimer: "", ready: false }`. A repeated `label=` works like a list.
export function parse(search) {
  var params = new URLSearchParams(search);
  var labels = [];
  params.getAll(LABEL).forEach(function (value) { labels = labels.concat(value.split(",")); });
  return { labels: unique(labels), claimer: params.get(CLAIMER) || "", ready: params.get(READY) === "1" };
}

// The query string (with its `?`, or "") of `current` with its filters replaced by `filters`; the other parameters, such
// as `card`, stay. A comma between labels is written as it is, and each label is escaped alone (spaces, `&`, unicode).
export function search(current, filters) {
  var params = new URLSearchParams(current);
  [LABEL, CLAIMER, READY].forEach(function (name) { params.delete(name); });
  var parts = [];
  if (params.size > 0) {
    parts.push(params.toString());
  }
  if (filters.labels.length > 0) {
    parts.push(LABEL + "=" + filters.labels.map(encodeURIComponent).join(","));
  }
  if (filters.claimer !== "") {
    parts.push(CLAIMER + "=" + encodeURIComponent(filters.claimer));
  }
  if (filters.ready) {
    parts.push(READY + "=1");
  }
  return parts.length > 0 ? "?" + parts.join("&") : "";
}

// How many filters are on, for the Filters button: each label, the agent and ready count one.
export function count(filters) {
  return filters.labels.length + (filters.claimer !== "" ? 1 : 0) + (filters.ready ? 1 : 0);
}

// The filters that are on, as the chips above the board show them: ready, the agent, then the labels in their order.
export function activeChips(filters) {
  var chips = [];
  if (filters.ready) {
    chips.push({ kind: "ready", name: "", text: "Ready" });
  }
  if (filters.claimer !== "") {
    chips.push({ kind: "claimer", name: filters.claimer, text: "Agent: " + filters.claimer });
  }
  filters.labels.forEach(function (label) {
    chips.push({ kind: "label", name: label, text: label });
  });
  return chips;
}

// The query of the link of card `id`: the card and the filters, so a new tab opens the same view.
export function cardSearch(filters, id) {
  return search("?card=" + id, filters);
}

export function active(filters) {
  return filters.labels.length > 0 || filters.claimer !== "" || filters.ready;
}

// Whether `card` shows: it has every selected label, is held by the selected agent, and is ready when asked.
export function matches(card, filters) {
  var labels = Array.isArray(card.labels) ? card.labels : [];
  return filters.labels.every(function (label) { return labels.indexOf(label) !== -1; })
    && (filters.claimer === "" || card.claimed_by === filters.claimer)
    && (!filters.ready || card.ready === true);
}

// The chips: the labels of the cards and the agents holding cards, sorted, plus what is selected even if no card has it
// any more (a stale link), so there is always a chip to take it off.
export function options(cards, filters) {
  var labels = [];
  var claimers = [];
  cards.forEach(function (card) {
    (Array.isArray(card.labels) ? card.labels : []).forEach(function (label) {
      if (selectable(label)) {
        labels.push(label);
      }
    });
    if (typeof card.claimed_by === "string") {
      claimers.push(card.claimed_by);
    }
  });
  return {
    labels: unique(labels.concat(filters.labels)).sort(),
    claimers: unique(claimers.concat(filters.claimer === "" ? [] : [filters.claimer])).sort(),
  };
}

export function toggleLabel(filters, label) {
  var has = filters.labels.indexOf(label) !== -1;
  var labels = has ? filters.labels.filter(function (one) { return one !== label; }) : filters.labels.concat([label]);
  return { labels: labels, claimer: filters.claimer, ready: filters.ready };
}

// One agent at a time: a card has one claimer. A second click on the same agent takes it off.
export function toggleClaimer(filters, name) {
  return { labels: filters.labels, claimer: filters.claimer === name ? "" : name, ready: filters.ready };
}

export function toggleReady(filters) {
  return { labels: filters.labels, claimer: filters.claimer, ready: !filters.ready };
}

export var NO_FILTERS = { labels: [], claimer: "", ready: false };
