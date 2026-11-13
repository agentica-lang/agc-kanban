// Stands in for app/javascript/board_store.js when board_markup.test.mjs draws the board page on the server side: the
// page gets a board with one card and no network, because the render does not wait for a fetch.
import { reactive } from "vue";

export function useBoard() {
  return reactive({
    board: { id: 1, name: "Project", columns: [{ id: 1, name: "Todo", position: 0, done: false }] },
    cards: [{ id: 7, title: "Fix login", column_id: 1, position: 0, priority: 1, claimed_by: null, labels: ["api"], depends_on: [], done: false }],
    feed: [],
    more: false,
    loading: false,
    loadError: false,
    error: "",
    flash: {},
    loadMore: function () {},
  });
}
