// What the lines between cards listen to, so that they are measured again when a card moves or changes size: any scroll
// below `host` (the board scrolls sideways and each column scrolls its cards; a scroll does not bubble, so it is heard
// on the way down), the resize of the window, and the size of `host` and of each card a line joins (a live edit of a
// title or a label changes a card's height and nothing else that the page knows of). `sync(elements)` says which cards
// are joined now. Returns { sync, stop }; `stop` takes everything off again.
export function watchLines(host, schedule, win, Observer) {
  var observer = null;
  var watched = new Set();
  host.addEventListener("scroll", schedule, { capture: true, passive: true });
  win.addEventListener("resize", schedule);
  if (typeof Observer === "function") {
    observer = new Observer(schedule);
    observer.observe(host);
  }
  return {
    sync: function (elements) {
      if (!observer) {
        return;
      }
      var now = new Set(elements);
      watched.forEach(function (element) {
        if (!now.has(element)) {
          observer.unobserve(element);
          watched.delete(element);
        }
      });
      now.forEach(function (element) {
        if (!watched.has(element)) {
          observer.observe(element);
          watched.add(element);
        }
      });
    },
    stop: function () {
      host.removeEventListener("scroll", schedule, { capture: true });
      win.removeEventListener("resize", schedule);
      observer && observer.disconnect();
      watched.clear();
    },
  };
}
