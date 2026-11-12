import { createApp } from "vue";
import "../stylesheets/application.scss";
import BoardPage from "./components/BoardPage.vue";
import BoardsPage from "./components/BoardsPage.vue";

// One script for every page: the view says which part runs. The login page needs none. Vue replaces the "Loading"
// text that the server put in #app.
var view = document.body.dataset.view;

if (view === "board") {
  createApp(BoardPage, { slug: document.body.dataset.slug }).mount("#app");
} else if (view === "boards") {
  createApp(BoardsPage).mount("#app");
}
