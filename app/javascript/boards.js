import { getJSON, h } from "./api.js";

// The list of boards: not live, a reload shows a new board.
export function startBoards(root) {
  getJSON("/api/boards").then(function (answer) {
    var list = h("ul", { class: "boards" });
    answer.boards.forEach(function (board) {
      list.appendChild(h("li", null, h("a", { href: "/boards/" + encodeURIComponent(board.slug) }, board.name)));
    });
    root.appendChild(h("main", null, h("h1", null, "Boards"), answer.boards.length ? list : h("p", { class: "empty" }, "No boards yet.")));
  });
}
