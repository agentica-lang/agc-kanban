import { h } from "./api.js";

// Draws the whole board from `state` ({ board, cards, feed, changed, more, loadMore }): a column is cheap to rebuild at
// this size, and a card that an event named is marked so that it flashes once. `feed` is newest first.
export function render(root, state) {
  var board = state.board;
  var byId = {};
  state.cards.forEach(function (card) { byId[card.id] = card; });
  var done = {};
  board.columns.forEach(function (column) { done[column.id] = column.done; });

  function blocked(card) {
    return !card.done && card.depends_on.some(function (id) { return byId[id] && !done[byId[id].column_id]; });
  }

  var columns = board.columns.slice().sort(function (a, b) { return a.position - b.position; }).map(function (column) {
    var cards = state.cards
      .filter(function (card) { return card.column_id === column.id; })
      .sort(function (a, b) { return a.position - b.position; });
    return h(
      "section",
      { class: "column" + (column.done ? " column-done" : "") },
      h("h2", null, column.name, h("span", { class: "count" }, cards.length + (column.wip_limit ? "/" + column.wip_limit : ""))),
      h("div", { class: "cards" }, cards.map(function (card) { return cardView(card, blocked(card), state.changed[card.id]); }))
    );
  });

  root.replaceChildren(
    h("header", { class: "top" }, h("a", { href: "/boards" }, "Boards"), h("h1", null, board.name)),
    h("main", { class: "board" }, columns),
    feedView(state)
  );
}

function cardView(card, isBlocked, isChanged) {
  var classes = ["card", "priority-" + card.priority];
  if (isChanged) { classes.push("changed"); }
  if (card.done) { classes.push("card-done"); }

  return h(
    "article",
    { class: classes.join(" ") },
    h("div", { class: "title" }, h("span", { class: "id" }, "#" + card.id), " ", card.title),
    h(
      "div",
      { class: "meta" },
      card.claimed_by ? h("span", { class: "claimer", style: "--hue:" + hue(card.claimed_by) }, card.claimed_by) : null,
      isBlocked ? h("span", { class: "blocked" }, "blocked by " + card.depends_on.map(function (id) { return "#" + id; }).join(" ")) : null,
      card.labels.map(function (label) { return h("span", { class: "label" }, label); })
    )
  );
}

function feedView(state) {
  return h(
    "aside",
    { class: "feed" },
    h("h2", null, "Activity"),
    h("ul", null, state.feed.map(function (event) {
      return h("li", null, h("b", null, event.kind), event.card_id !== null ? " #" + event.card_id : "", " ", h("span", { class: "actor" }, event.actor));
    })),
    state.more ? h("button", { class: "more", type: "button", onclick: state.loadMore }, "Ver m\u00e1s") : null
  );
}

// A color from the name, so one agent keeps one color.
function hue(name) {
  var sum = 0;
  for (var i = 0; i < name.length; i++) {
    sum = (sum * 31 + name.charCodeAt(i)) % 360;
  }
  return sum;
}
