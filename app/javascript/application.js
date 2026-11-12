import { startBoard } from "./board.js";
import { startBoards } from "./boards.js";

// One script for every page: the view says which part runs. The login page needs none.
var view = document.body.dataset.view;
var root = document.getElementById("app");

if (view === "board") {
  startBoard(root, document.body.dataset.slug);
} else if (view === "boards") {
  startBoards(root);
}
