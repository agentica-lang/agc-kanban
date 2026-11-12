// The thin scrollbars hide while idle (thin-scroll in _tokens.scss): an area that scrolls gets the class `scrolling`,
// which goes off 1.5 s after its last scroll. The board's own hover is the whole page, so for it the pointer near its
// bottom edge counts as a scroll. Scroll events do not bubble, so one listener catches them on the way down.
var IDLE_MS = 1500;
// The height of the strip above the board's bottom edge that shows its bar: the bar and a little more.
var EDGE_PX = 14;

var timers = new WeakMap();

function show(area) {
  area.classList.add("scrolling");
  clearTimeout(timers.get(area));
  timers.set(area, setTimeout(function () {
    area.classList.remove("scrolling");
    timers.delete(area);
  }, IDLE_MS));
}

function onScroll(event) {
  if (event.target instanceof Element) {
    show(event.target);
  }
}

function onPointerMove(event) {
  if (event.pointerType !== "mouse" || !(event.target instanceof Element)) {
    return;
  }
  var board = event.target.closest(".board");
  if (board && board.scrollWidth > board.clientWidth && board.getBoundingClientRect().bottom - event.clientY <= EDGE_PX) {
    show(board);
  }
}

export function hideIdleScrollbars() {
  document.addEventListener("scroll", onScroll, { capture: true, passive: true });
  document.addEventListener("pointermove", onPointerMove, { passive: true });
}
