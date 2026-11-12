import { cut } from "./feed.js";

// The links of a card are untrusted text. One is a link only when it parses as an http(s) URL; anything else shows as
// plain text. The label is short: a GitHub pull request or issue by its number ("PR #7", whatever follows the number),
// any other URL by its host and path.
var LABEL_MAX = 60;
var GITHUB = /^\/[^/]+\/[^/]+\/(pull|issues)\/(\d+)(\/|$)/;

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
