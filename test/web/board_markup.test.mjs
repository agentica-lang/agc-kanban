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

var ROOT = new URL("../../", import.meta.url).pathname;
var server = await createServer({
  root: ROOT,
  configFile: false,
  logLevel: "error",
  appType: "custom",
  server: { middlewareMode: true, hmr: false, watch: null },
  plugins: [vue()],
  optimizeDeps: { noDiscovery: true, include: [] },
});
after(function () { return server.close(); });
var Card = (await server.ssrLoadModule("/app/javascript/components/Card.vue")).default;
var CardPanel = (await server.ssrLoadModule("/app/javascript/components/CardPanel.vue")).default;
var FilterBar = (await server.ssrLoadModule("/app/javascript/components/FilterBar.vue")).default;
var Drawer = (await server.ssrLoadModule("/app/javascript/components/Drawer.vue")).default;

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
  assert.ok(html.includes('<span class="label">x,y</span>'), "a label with a comma cannot filter, so it is no button");
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
});

test("the card drawer is a modal dialog and the other drawers are plain panels", async function () {
  var modal = await draw(Drawer, { title: "Card #7", modal: true }, "");
  assert.match(modal, /<aside[^>]*class="drawer drawer-modal"[^>]*role="dialog"[^>]*aria-modal="true"/);
  var plain = await draw(Drawer, { title: "Activity" }, "");
  assert.doesNotMatch(plain, /drawer-modal|role=|aria-modal/);
});
