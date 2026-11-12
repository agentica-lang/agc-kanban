import { h } from "vue";

// A small Markdown for card bodies and comments, drawn as Vue nodes: every piece of the text is a text node, so no
// markup of the text ever reaches the page (no v-html). It reads fenced code, headings, lists, quotes and paragraphs
// (a line break is kept), and inline code, bold, italic and links. A link goes only to http(s), and a bare URL is a
// link too, so issue and PR links are clickable.
var INLINE = /(`[^`]+`)|\*\*([^*]+)\*\*|\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(https?:\/\/[^\s<>]*[^\s<>.,;:!?'")\]])|(?:^|(?<=\s))[*_]([^*_\s](?:[^*_]*[^*_\s])?)[*_]/g;
var FENCE = /^```/;
var HEADING = /^(#{1,6})\s+(.*)$/;
var BULLET = /^\s*[-*+]\s+(.*)$/;
var NUMBERED = /^\s*\d+[.)]\s+(.*)$/;
var QUOTE = /^>\s?(.*)$/;

function link(href, text) {
  return h("a", { href: href, target: "_blank", rel: "noopener noreferrer" }, text);
}

function inline(text) {
  var nodes = [];
  var last = 0;
  text.replace(INLINE, function (match, code, bold, label, href, bare, italic, offset) {
    if (offset > last) {
      nodes.push(text.slice(last, offset));
    }
    if (code) {
      nodes.push(h("code", code.slice(1, -1)));
    } else if (bold) {
      nodes.push(h("strong", inline(bold)));
    } else if (label) {
      nodes.push(link(href, label));
    } else if (bare) {
      nodes.push(link(bare, bare));
    } else {
      nodes.push(h("em", inline(italic)));
    }
    last = offset + match.length;
    return match;
  });
  if (last < text.length) {
    nodes.push(text.slice(last));
  }
  return nodes;
}

// The lines of a paragraph or a quote, with their breaks.
function broken(lines) {
  var nodes = [];
  lines.forEach(function (line, index) {
    if (index > 0) {
      nodes.push(h("br"));
    }
    nodes.push.apply(nodes, inline(line));
  });
  return nodes;
}

// The run of lines from `start` that `pattern` matches, with what it captured.
function run(lines, start, pattern) {
  var items = [];
  var match;
  while (start + items.length < lines.length && (match = pattern.exec(lines[start + items.length]))) {
    items.push(match[1]);
  }
  return items;
}

function blocks(text) {
  var lines = text.replace(/\r\n?/g, "\n").split("\n");
  var nodes = [];
  var i = 0;
  while (i < lines.length) {
    var line = lines[i];
    var heading = HEADING.exec(line);
    var items;
    if (line.trim() === "") {
      i += 1;
    } else if (FENCE.test(line)) {
      var end = i + 1;
      while (end < lines.length && !FENCE.test(lines[end])) {
        end += 1;
      }
      nodes.push(h("pre", h("code", lines.slice(i + 1, end).join("\n"))));
      i = end + 1;
    } else if (heading) {
      nodes.push(h("h4", inline(heading[2])));
      i += 1;
    } else if ((items = run(lines, i, BULLET)).length || (items = run(lines, i, NUMBERED)).length) {
      var tag = BULLET.test(line) ? "ul" : "ol";
      nodes.push(h(tag, items.map(function (item) { return h("li", inline(item)); })));
      i += items.length;
    } else if ((items = run(lines, i, QUOTE)).length) {
      nodes.push(h("blockquote", broken(items)));
      i += items.length;
    } else {
      var start = i;
      while (i < lines.length && lines[i].trim() !== "" && !FENCE.test(lines[i]) && !HEADING.test(lines[i]) &&
        !BULLET.test(lines[i]) && !NUMBERED.test(lines[i]) && !QUOTE.test(lines[i])) {
        i += 1;
      }
      nodes.push(h("p", broken(lines.slice(start, i))));
    }
  }
  return nodes;
}

// `<Markdown :text="..." />`
export var Markdown = {
  props: { text: String },
  setup: function (props) {
    return function () {
      return h("div", { class: "md" }, blocks(props.text || ""));
    };
  },
};
