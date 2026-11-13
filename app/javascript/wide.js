import { onBeforeUnmount, ref } from "vue";

// The width from which the card opens as a modal over the board. The stylesheet's `tokens.$wide` is the same
// number (styles.test.mjs checks it), so the look and `inert` change at the same pixel. A hair above the phone's
// `max-width: 700px`, so no fractional width falls in neither.
export var WIDE = "(min-width: 700.02px)";

// Whether the window is wide, kept current when it is resized. Without `matchMedia` it is false: a phone layout.
export function useWide() {
  var query = typeof window !== "undefined" && window.matchMedia ? window.matchMedia(WIDE) : null;
  var wide = ref(query ? query.matches : false);
  if (query) {
    var onChange = function (event) { wide.value = event.matches; };
    query.addEventListener("change", onChange);
    onBeforeUnmount(function () { query.removeEventListener("change", onChange); });
  }
  return wide;
}
