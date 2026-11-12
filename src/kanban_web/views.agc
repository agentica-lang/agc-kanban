## The pages: a shell that names the built assets, and the script draws the rest from `/api/`.

import EAG from "std/eag"
import Bond from "pkg/bond/bond"
import AssetNames from "asset_names"

# The views that the script draws (application.js): only they get `#app` and its loading text.
SCRIPTED_VIEWS = ["boards", "board"]

## The login form, with a `note` about the last try ("" shows none).
export def login(note: String) -> String = layout("Sign in", "login", "", form(note))

## The page of the list of boards.
export def boards() -> String = layout("Boards", "boards", "", "")

## The page of one board; the script reads `slug` from the page.
export def board(slug: String) -> String = layout(slug, "board", slug, "")

def form(note: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <form class="login" method="post" action="/login">
      <h1>agc-kanban</h1>
    <% if not note.empty? %>
      <p class="note"><%= note %></p>
    <% end %>
      <label>API key <input type="password" name="key" autocomplete="current-password" autofocus required></label>
      <button type="submit">Sign in</button>
    </form>
  EAG
end

# `content` is markup of this file (the form), never a value of a client; `title` and `slug` are escaped. A view of
# SCRIPTED_VIEWS gets `#app`, with the text that shows until the script mounts.
def layout(title: String, view: String, slug: String, content: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title><%= title %> - agc-kanban</title>
      <link rel="stylesheet" href="<%= AssetNames.STYLESHEET %>">
      <script defer src="<%= AssetNames.SCRIPT %>"></script>
    </head>
    <body data-view="<%= view %>" data-slug="<%= slug %>">
    <% if view != "login" %>
      <form class="logout" method="post" action="/logout"><button type="submit">Sign out</button></form>
    <% end %>
    <%== content %>
    <% if SCRIPTED_VIEWS.include?(view) %>
      <div id="app"><p class="empty">Loading...</p></div>
    <% end %>
    </body>
    </html>
  EAG
end
