// A click outside the open panel of the drawer closes it on a wide screen, as the backdrop does on a phone. Only a
// plain click on what has no job of its own does: not in the panel, not on a card (it opens that card, and its agent
// and label chips filter with the panel kept open), not on the header buttons or Sign out, not on the filter bar, and
// not on the backdrop (it closes the panel itself). A text selection that starts in the panel and ends outside it is no
// click outside: `down` is the path of the press (`composedPath()` of the pointerdown, [] when unknown).
// Paths, not `closest`: the click's own handler may have re-rendered its target out of the page (the theme button swaps
// its icon) before this one runs, and a path keeps the ancestors the event went through.
var KEPT = "#drawer, .card, .top, .logout, .filters, .filters-none, .backdrop";

function within(path, selector) {
  return path.some(function (node) { return typeof node.matches === "function" && node.matches(selector); });
}

export function closesPanel(event, down) {
  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) {
    return false;
  }
  return !within(down, "#drawer") && !within(event.path, KEPT);
}
