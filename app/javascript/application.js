import { createApp } from "vue";
import "../stylesheets/application.scss";
import BoardPage from "./components/BoardPage.vue";
import { hideIdleScrollbars } from "./scrollbars.js";

// One script for every page: the view says which part runs. The login page and the home page need none: the server
// draws them. Vue replaces the "Loading" text that the server put in #app.
var view = document.body.dataset.view;

hideIdleScrollbars();

if (view === "board") {
  createApp(BoardPage, { slug: document.body.dataset.slug }).mount("#app");
}
