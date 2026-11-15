// Takes the viewer to a card: a chip of a related card calls this. A column that is collapsed opens for this visit only
// (`collapsed.reveal`, which saves nothing), the page scrolls to the card and its title takes the focus, so Enter opens
// it. A card that the page does not draw (the filters hide it, or it is not on the board) opens in the panel instead.
// `env` is what the page has: `cards()`, `collapsed`, `document`, `reduced()` (whether the viewer asks for less motion),
// `open(id)` and `later(fn)` (after the next render).
export function reveal(env, id) {
  var found = env.cards().find(function (one) { return one.id === id; });
  if (found && env.collapsed.has(found.column_id)) {
    env.collapsed.reveal(found.column_id);
  }
  env.later(function () {
    var link = env.document.querySelector('.board .card a.title[data-card="' + id + '"]');
    if (!link) {
      env.open(id);
      return;
    }
    link.scrollIntoView({ block: "center", inline: "center", behavior: env.reduced() ? "auto" : "smooth" });
    link.focus({ preventScroll: true });
  });
}
