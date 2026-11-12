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
  forget();
  if (event.target instanceof Element) {
    show(event.target);
  }
}

// The board and its bottom edge, read on the first move after a resize or a scroll and kept until the next one, so
// that most moves cost one comparison. The board fills the page to its bottom, so nothing else moves that edge.
var board = null;
var boardBottom = 0;

function forget() {
  board = null;
}

function onPointerMove(event) {
  if (event.pointerType !== "mouse") {
    return;
  }
  if (board === null || !board.isConnected) {
    board = document.querySelector(".board");
    if (board === null) {
      return;
    }
    boardBottom = board.getBoundingClientRect().bottom;
  }
  if (boardBottom - event.clientY <= EDGE_PX && event.clientY <= boardBottom && board.scrollWidth > board.clientWidth &&
    event.target instanceof Element && board.contains(event.target)) {
    show(board);
  }
}

export function hideIdleScrollbars() {
  document.addEventListener("scroll", onScroll, { capture: true, passive: true });
  document.addEventListener("pointermove", onPointerMove);
  window.addEventListener("resize", forget);
}
