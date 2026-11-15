// `make test` runs this with `node --test`: the markup of a card on the board and of the active filters above it, drawn
// on the server side by Vue from the real components (loaded through Vite, as the build does), with the filters read
// from a URL as the page reads them. It checks what a screen reader and the keyboard see: no control inside the card's
// link, each chip that filters is its own button, and `?label=` shows its chips.
import assert from "node:assert/strict";
import { after, test } from "node:test";
import { createServer } from "vite";
import vue from "@vitejs/plugin-vue";
import { createSSRApp, ref } from "vue";
import { renderToString } from "vue/server-renderer";
import { useFilters } from "../../app/javascript/filter_store.js";
import { chipStyle } from "../../app/javascript/labels.js";

var ROOT = new URL("../../", import.meta.url).pathname;
var server = await createServer({
  root: ROOT,
  configFile: false,
  logLevel: "error",
  appType: "custom",
  server: { middlewareMode: true, hmr: false, watch: null },
  plugins: [vue()],
  // The board page reads its data from the network; the render gets a fixed board instead.
  resolve: { alias: [{ find: /^.*\/board_store\.js$/, replacement: ROOT + "test/web/support/board_store.js" }] },
  optimizeDeps: { noDiscovery: true, include: [] },
});
after(function () { return server.close(); });
var Card = (await server.ssrLoadModule("/app/javascript/components/Card.vue")).default;
var CardPanel = (await server.ssrLoadModule("/app/javascript/components/CardPanel.vue")).default;
var FilterPanel = (await server.ssrLoadModule("/app/javascript/components/FilterPanel.vue")).default;
var FilterBar = (await server.ssrLoadModule("/app/javascript/components/FilterBar.vue")).default;
var Drawer = (await server.ssrLoadModule("/app/javascript/components/Drawer.vue")).default;
var ArchivePanel = (await server.ssrLoadModule("/app/javascript/components/ArchivePanel.vue")).default;
var BoardPage = (await server.ssrLoadModule("/app/javascript/components/BoardPage.vue")).default;
var Column = (await server.ssrLoadModule("/app/javascript/components/Column.vue")).default;

// The page code reads the filters from `location`; a plain object stands in for it.
function filtersAt(search) {
  globalThis.location = { search: search, href: "http://kanban.test/boards/p" + search };
  globalThis.history = { state: null, replaceState: function () {} };
  globalThis.window = { addEventListener: function () {}, removeEventListener: function () {} };
  return useFilters();
}

function draw(component, props, search) {
  var filter = filtersAt(search);
  var app = createSSRApp(component, Object.assign({ store: filter }, props));
  app.provide("filter", filter);
  app.provide("openCard", function () {});
  app.provide("openCardId", ref(null));
  app.provide("labelStyle", function (name) { return chipStyle({ api: "#0075ca", ui: "#fbca04" }[name]) || null; });
  return renderToString(app);
}

function card(extra) {
  return Object.assign({ id: 7, title: "Fix login", priority: 1, claimed_by: null, labels: [], depends_on: [], done: false }, extra);
}

function buttons(html) {
  return Array.from(html.matchAll(/<button\b[^>]*>([^<]*)<\/button>/g)).map(function (one) { return one[0]; });
}

test("a card is a box with one link, and its agent and label chips are buttons outside the link", async function () {
  var html = await draw(Card, { card: card({ claimed_by: "line 1", labels: ["api", "two words", "x,y"] }), blocked: false, flash: 0 }, "?label=api");
  assert.ok(html.replace(/<!--[\s\S]*?-->/g, "").startsWith("<div class=\"card "), "the card is not a link");
  var anchors = html.match(/<a\b[^>]*>[\s\S]*?<\/a>/g);
  assert.equal(anchors.length, 1);
  assert.ok(anchors[0].includes('href="?card=7&amp;label=api"'), "the link keeps the filters");
  assert.equal(/<button|role="button"|tabindex/.test(anchors[0]), false, "a control inside the link");
  var chips = buttons(html);
  assert.equal(chips.length, 3);
  assert.ok(chips[0].includes("claimer") && chips[0].includes("line 1") && chips[0].includes('aria-pressed="false"'));
  assert.ok(chips[1].includes(">api<") && chips[1].includes('aria-pressed="true"'));
  assert.ok(chips[2].includes(">two words<") && chips[2].includes('aria-pressed="false"'));
  assert.ok(/<span class="label"[^>]*>x,y<\/span>/.test(html), "a label with a comma cannot filter, so it is no button");
});

test("a label chip takes the color of its board, with the ink for it, on the card and in the card panel", async function () {
  var html = await draw(Card, { card: card({ labels: ["api", "ui"] }), blocked: false, flash: 0 }, "");
  assert.ok(html.includes('style="background:#0075ca;color:#ffffff"'), "the chip has the color of its label");
  assert.ok(html.includes('style="background:#fbca04;color:#1f2328"'), "a light color gets the dark ink");
  var plain = await draw(Card, { card: card({ labels: ["other"] }), blocked: false, flash: 0 }, "");
  assert.equal(plain.includes("background"), false, "a label with no color keeps the plain chip");
});

test("a card with no labels and no agent has the link and no chip", async function () {
  var html = await draw(Card, { card: card(), blocked: false, flash: 0 }, "");
  assert.equal((html.match(/<a\b/g) || []).length, 1);
  assert.deepEqual(buttons(html), []);
  assert.ok(html.includes('href="?card=7"'));
});

test("?label= and the other filters of the URL show as chips above the board, each with a way to take it off", async function () {
  var html = await draw(FilterBar, { shown: 2 }, "?label=api,two+words&claimer=line1&ready=1");
  assert.ok(html.includes('aria-label="Active filters"'));
  ["Remove filter Ready", "Remove filter Agent: line1", "Remove filter api", "Remove filter two words"].forEach(function (name) {
    assert.ok(html.includes('aria-label="' + name + '"'), name);
  });
  assert.ok(html.includes(">Clear</button>"));
  assert.equal((await draw(FilterBar, { shown: 2 }, "")).includes("filters"), false, "no filter, no bar");
});

test("the panel of an archived card says it is archived, and the panel of any other does not", async function () {
  var detail = function (extra) {
    var full = card(Object.assign({ board: "p", column: "Todo", labels: [], links: [], blocks: [], body: "" }, extra));
    return { detail: { card: full, comments: [], times: null }, error: "" };
  };
  var archived = await draw(CardPanel, { state: detail({ archived_at: 1000 }), slug: "p" }, "");
  assert.match(archived, /<dt>Archived<\/dt>/);
  var open = await draw(CardPanel, { state: detail({ archived_at: null }), slug: "p" }, "");
  assert.equal(open.includes("Archived"), false);
  assert.ok(archived.includes(">Unarchive</button>") && !archived.includes(">Archive</button>"));
  assert.ok(open.includes(">Archive</button>") && !open.includes(">Unarchive</button>"));
});

test("the archive drawer archives the done cards older than 3 days by default and lists the archived cards", async function () {
  var archived = [{ id: 4, title: "Old <b>one</b>", archived_at: 1000 }];
  var state = { archived: archived, archivedMax: 200, watchArchived: false, actionError: "", busy: false, loadArchived: function () {}, archiveDone: function () {}, unarchiveCard: function () {} };
  var html = await draw(ArchivePanel, { state: state }, "");
  assert.match(html, /Archive done cards older than\s*<input[^>]*value="3"/);
  assert.equal(state.watchArchived, true, "the list follows the archive events while the panel is open");
  assert.ok(html.includes("Archived (1)") && html.includes("#4"));
  assert.ok(html.includes("Old &lt;b&gt;one&lt;/b&gt;") && !html.includes("<b>one</b>"), "titles are text");
  assert.ok(html.includes(">Unarchive</button>"));
  var none = await draw(ArchivePanel, { state: Object.assign({}, state, { archived: [] }) }, "");
  assert.ok(none.includes("No archived card."));
});

// The opening tags of `html` that have the class `name`, each as { tag, attrs } so a test does not depend on the order
// of the attributes.
function tagsWith(html, name) {
  return Array.from(html.matchAll(/<([a-z][\w-]*)\b([^>]*)>/g)).map(function (one) {
    var attrs = {};
    Array.from(one[2].matchAll(/([\w-]+)(?:="([^"]*)")?/g)).forEach(function (pair) { attrs[pair[1]] = pair[2] === undefined ? "" : pair[2]; });
    return { tag: one[1], attrs: attrs };
  }).filter(function (one) { return (one.attrs.class || "").split(" ").includes(name); });
}

function only(html, name) {
  var found = tagsWith(html, name);
  assert.equal(found.length, 1, name + " x" + found.length);
  return found[0];
}

// The board page with `search` as its URL, on a screen that is wide or not (`matchMedia`). The Sign out form is outside
// the app, so a plain object stands in for it.
async function drawPage(search, wide) {
  var logout = { inert: false };
  filtersAt(search);
  globalThis.window.matchMedia = function () {
    return { matches: wide, addEventListener: function () {}, removeEventListener: function () {} };
  };
  globalThis.document = {
    addEventListener: function () {},
    removeEventListener: function () {},
    documentElement: { dataset: {} },
    querySelector: function (selector) { return selector === ".logout" ? logout : null; },
  };
  globalThis.getSelection = function () { return { isCollapsed: true }; };
  var app = createSSRApp(BoardPage, { slug: "p" });
  return { html: await renderToString(app), logout: logout };
}

test("the open card is a modal over the board on a wide screen: a dialog, the rest inert, the backdrop modal", async function () {
  var { html, logout } = await drawPage("?card=7&label=api", true);
  assert.ok(only(html, "backdrop").attrs.class.split(" ").includes("backdrop-modal"));
  var drawer = only(html, "drawer");
  assert.ok(drawer.attrs.class.split(" ").includes("drawer-modal"));
  assert.equal(drawer.attrs.role, "dialog");
  assert.equal(drawer.attrs["aria-modal"], "true");
  // What is behind the window: the header, the filter bar, the board (and the Sign out form, outside the app).
  ["top", "filters", "board"].forEach(function (name) {
    assert.ok("inert" in only(html, name).attrs, name + " is not inert");
  });
  assert.equal(drawer.attrs.inert, undefined);
  assert.equal(logout.inert, true);
});

test("on a phone the card is a drawer beside the board: no dialog role and nothing inert", async function () {
  var { html, logout } = await drawPage("?card=7&label=api", false);
  var drawer = only(html, "drawer");
  assert.equal(drawer.attrs.role, undefined);
  assert.equal(drawer.attrs["aria-modal"], undefined);
  ["top", "filters", "board"].forEach(function (name) {
    assert.equal("inert" in only(html, name).attrs, false, name + " is inert");
  });
  assert.equal(logout.inert, false);
});

test("a board with no card open has no backdrop-modal, no dialog and nothing inert", async function () {
  var { html } = await drawPage("", true);
  assert.equal(tagsWith(html, "backdrop").length, 0);
  assert.equal(tagsWith(html, "drawer").length, 0);
  assert.equal("inert" in only(html, "board").attrs, false);
});

test("the card drawer is a dialog only when it is told it is one", async function () {
  var modal = await draw(Drawer, { title: "Card #7", modal: true, dialog: true }, "");
  var drawer = only(modal, "drawer");
  assert.ok(drawer.attrs.class.split(" ").includes("drawer-modal"));
  assert.equal(drawer.attrs.role, "dialog");
  assert.equal(drawer.attrs["aria-modal"], "true");
  var phone = only(await draw(Drawer, { title: "Card #7", modal: true }, ""), "drawer");
  assert.equal(phone.attrs.role, undefined);
  assert.equal(phone.attrs["aria-modal"], undefined);
  var plain = await draw(Drawer, { title: "Activity" }, "");
  assert.doesNotMatch(plain, /drawer-modal|role=|aria-modal/);
});

test("the panel of a card has the text before the facts, and the facts are a div, not an aside", async function () {
  var full = card({ board: "p", column: "Todo", labels: [], links: [], blocks: [], body: "Hello" });
  var html = await draw(CardPanel, { state: { detail: { card: full, comments: [], times: null }, error: "" }, slug: "p" }, "");
  assert.ok(html.indexOf("detail-main") < html.indexOf("detail-side"));
  assert.equal(only(html, "detail-side").tag, "div");
  assert.equal(/<aside/.test(html), false);
  assert.equal(tagsWith(html, "with-banner").length, 0, "no banner, no banner row");
  var failing = await draw(CardPanel, { state: { detail: { card: full, comments: [], times: null }, error: "down" }, slug: "p" }, "");
  assert.equal(tagsWith(failing, "with-banner").length, 1);
});

test("the header has a Reload board button, enabled while the board is not being fetched", async function () {
  var { html } = await drawPage("", true);
  var tag = html.match(/<button\b[^>]*aria-label="Reload board"[^>]*>/);
  assert.ok(tag, "no reload button");
  assert.ok(tag[0].includes('title="Reload board"'));
  assert.equal(tag[0].includes("disabled"), false);
});

test("the filters drawer has a search box that keeps its text, and says how many cards were found", async function () {
  var search = { q: ref("logi"), failed: ref(false), set: function () {}, clear: function () {}, on: function () { return true; }, count: function () { return 1; } };
  var html = await draw(FilterPanel, { cards: [], search: search }, "");
  var box = only(html, "search-input");
  assert.equal(box.tag, "input");
  assert.equal(box.attrs.type, "search");
  assert.equal(box.attrs["aria-label"], "Search cards");
  assert.equal(box.attrs.value, "logi");
  assert.ok(html.includes("1 card found, best first"));
  assert.ok(html.includes(">Clear all</button>"), "a search counts as something to clear");
});

test("the filters drawer shows each label in its color, with a color input for it", async function () {
  var search = { q: ref(""), failed: ref(false), set: function () {}, clear: function () {}, on: function () { return false; }, count: function () { return null; } };
  var labels = [{ id: 3, name: "api", color: "#0075ca" }];
  var html = await draw(FilterPanel, { cards: [card({ labels: ["api", "other"] })], search: search, labels: labels }, "");
  assert.ok(html.includes('style="background:#0075ca;color:#ffffff"'), "the chip has its color");
  assert.equal((html.match(/type="color"/g) || []).length, 1, "a label the board has no row for has no input");
  assert.ok(html.includes('value="#0075ca"') && html.includes('aria-label="Color of api"'));
});

test("a column header has a collapse button and the count; a collapsed column is one expand button with the count", async function () {
  var column = { id: 3, name: "Review", done: false, wip_limit: 4 };
  var cards = [card({ id: 7 }), card({ id: 8, title: "Second" })];
  var open = await draw(Column, { column: column, cards: cards, total: 2, filtering: false, blocked: {}, flash: {}, collapsed: false }, "");
  var collapse = only(open, "column-collapse");
  assert.equal(collapse.tag, "button");
  assert.match(open, /<h2><span class="name">Review<\/span><span class="count">2\/4<\/span><\/h2><button/, "the heading has the name and the count only");
  assert.equal(collapse.attrs["aria-expanded"], "true");
  assert.equal(collapse.attrs["aria-label"], "Collapse column Review");
  assert.match(open, /<span class="count"[^>]*>2\/4<\/span>/);
  assert.equal(tagsWith(open, "card").length, 2);
  assert.equal(tagsWith(open, "column-collapsed").length, 0);

  var shut = await draw(Column, { column: column, cards: cards.slice(0, 1), total: 2, filtering: true, blocked: {}, flash: {}, collapsed: true }, "");
  assert.ok(only(shut, "column").attrs.class.split(" ").includes("column-collapsed"));
  var strip = only(shut, "column-strip");
  assert.equal(strip.tag, "button");
  assert.equal(strip.attrs["aria-expanded"], "false");
  assert.equal(strip.attrs["aria-label"], "Expand column Review, 1 of 2 cards");
  assert.match(shut, /<h2 class="strip-heading"><button[^>]*class="column-strip"/, "the strip is inside a heading");
  assert.match(shut, /<span class="count" title="1 of 2 cards">1<\/span><span class="name">Review<\/span>/);
  assert.equal(tagsWith(shut, "card").length, 0, "a collapsed column draws no card");
  assert.equal(tagsWith(shut, "column-collapse").length, 0);
});

test("the board page draws the columns that this viewer collapsed on this board as strips", async function () {
  var kept = { "agc-kanban.collapsed.p": "[1,9]" };
  var store = {
    getItem: function (key) { return kept[key] || null; },
    setItem: function (key, value) { kept[key] = value; },
    removeItem: function (key) { delete kept[key]; },
  };
  Object.defineProperty(globalThis, "localStorage", { configurable: true, writable: true, value: store });
  try {
    var { html } = await drawPage("", true);
    assert.equal(only(html, "column-strip").attrs["aria-label"], "Expand column Todo, 1 card");
    assert.equal(kept["agc-kanban.collapsed.p"], "[1]", "the id of a column the board does not have is dropped");
    kept = {};
    var { html: other } = await drawPage("", true);
    assert.equal(tagsWith(other, "column-strip").length, 0);
    assert.equal(only(other, "column-collapse").attrs["aria-label"], "Collapse column Todo");
  } finally {
    delete globalThis.localStorage;
  }
});
