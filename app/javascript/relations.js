// The relations between the cards of a board, from `depends_on` and `blocks` of each card, and the line that joins two
// cards on the page. Pure, so it is tested without a page.

// A dependency that is not on the board (archived, or gone) does not block: the server says the same.
export function dependency(byId, id) {
  var found = byId[id];
  if (!found) {
    return { id: id, known: false, done: true, column: "" };
  }
  return { id: id, known: true, done: found.done, column: found.column };
}

export function indexOf(cards) {
  var byId = {};
  cards.forEach(function (card) { byId[card.id] = card; });
  return byId;
}

// The ids that a card is related to, each once: the cards it depends on and the cards that depend on it.
export function related(card) {
  var ids = [];
  (card.depends_on || []).concat(card.blocks || []).forEach(function (id) {
    if (ids.indexOf(id) === -1 && id !== card.id) {
      ids.push(id);
    }
  });
  return ids;
}

// Each pair once, from the card that is needed to the card that needs it, and only when both are among `cards`.
export function pairs(cards) {
  var byId = indexOf(cards);
  var seen = {};
  var found = [];
  cards.forEach(function (card) {
    (card.depends_on || []).forEach(function (id) {
      var key = id + ">" + card.id;
      if (byId[id] && !seen[key]) {
        seen[key] = true;
        found.push({ from: id, to: card.id });
      }
    });
    (card.blocks || []).forEach(function (id) {
      var key = card.id + ">" + id;
      if (byId[id] && !seen[key]) {
        seen[key] = true;
        found.push({ from: card.id, to: id });
      }
    });
  });
  return found;
}

// How a card looks while `hot` (the card that is hovered or focused, or null) is marked: "self", "related" or "dim"; ""
// when nothing is marked.
export function mark(byId, hot, id) {
  if (hot === null || hot === undefined || !byId[hot]) {
    return "";
  }
  if (hot === id) {
    return "self";
  }
  return related(byId[hot]).indexOf(id) !== -1 ? "related" : "dim";
}

// The curve from the card `a` (needed) to the card `b` (needing it); both are { left, right, top, bottom } in the same
// coordinates. It leaves the side of `a` that faces `b` and enters the side of `b` that faces `a`; two cards that
// overlap sideways (the same column) are joined on their right sides, with the curve bulging out.
var BULGE = 28;

export function curve(a, b) {
  var ay = (a.top + a.bottom) / 2;
  var by = (b.top + b.bottom) / 2;
  var x1;
  var x2;
  var c1;
  var c2;
  if (a.right <= b.left) {
    x1 = a.right;
    x2 = b.left;
    var reach = Math.max(BULGE, (x2 - x1) / 2);
    c1 = x1 + reach;
    c2 = x2 - reach;
  } else if (b.right <= a.left) {
    x1 = a.left;
    x2 = b.right;
    var back = Math.max(BULGE, (x1 - x2) / 2);
    c1 = x1 - back;
    c2 = x2 + back;
  } else {
    x1 = a.right;
    x2 = b.right;
    c1 = x1 + BULGE;
    c2 = x2 + BULGE;
  }
  var round = function (n) { return Math.round(n * 10) / 10; };
  return "M" + round(x1) + " " + round(ay) + " C" + round(c1) + " " + round(ay) + " " + round(c2) + " " + round(by) + " " + round(x2) + " " + round(by);
}

// Whether the middle of `box` is inside `clip`: a card that its column has scrolled out of sight, or the board has, has
// no line (the line would hang in the air).
export function visible(box, clip) {
  var x = (box.left + box.right) / 2;
  var y = (box.top + box.bottom) / 2;
  return x >= clip.left && x <= clip.right && y >= clip.top && y <= clip.bottom;
}
