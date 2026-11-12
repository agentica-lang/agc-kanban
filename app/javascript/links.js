import { cut } from "./feed.js";

// The links of a card are untrusted text. One is a link only when it parses as an http(s) URL; anything else shows as
// plain text. The label is short: a GitHub pull request or issue by its number ("PR #7", whatever follows the number),
// any other URL by its host and path.
var LABEL_MAX = 60;
var GITHUB = /^\/[^/]+\/[^/]+\/(pull|issues)\/(\d+)(\/|$)/;

// The id of the card that `href` names when it is a link to a card of the board `slug` of this site (`/boards/slug?card=12`,
// as an absolute URL, which is what Markdown links are); null for any other link. The page opens such a link in its
// panel, as a click on a card does.
export function boardCardId(href, origin, slug) {
  var parsed = null;
  try {
    parsed = new URL(href);
  } catch (_error) {
    return null;
  }
  var path = "/boards/" + encodeURIComponent(slug);
  if (parsed.origin !== origin || (parsed.pathname !== path && parsed.pathname !== path + "/")) {
    return null;
  }
  var raw = parsed.searchParams.get("card");
  var id = Number(raw);
  return /^\d+$/.test(raw || "") && id > 0 && Number.isSafeInteger(id) ? id : null;
}

export function cardLink(url) {
  var text = typeof url === "string" ? url : "";
  var parsed = null;
  try {
    parsed = new URL(text);
  } catch (_error) {
    parsed = null;
  }
  if (!parsed || (parsed.protocol !== "http:" && parsed.protocol !== "https:")) {
    return { href: null, label: cut(text, LABEL_MAX) };
  }
  var github = parsed.hostname === "github.com" ? GITHUB.exec(parsed.pathname) : null;
  if (github) {
    return { href: text, label: (github[1] === "pull" ? "PR #" : "issue #") + github[2] };
  }
  return { href: text, label: cut(parsed.host + parsed.pathname.replace(/\/+$/, ""), LABEL_MAX) };
}
