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
# SCRIPTED_VIEWS gets `#app`, with the text that shows until the script mounts. The inline script, before the
# stylesheet, applies the saved theme (the key of app/javascript/theme.js) so a dark page never paints light first; the
# server sends no Content-Security-Policy, so it runs. A value other than "light" or "dark" leaves the system setting.
def layout(title: String, view: String, slug: String, content: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title><%= title %> - agc-kanban</title>
      <script>(function () { try { var theme = localStorage.getItem("agc-kanban.theme"); if (theme === "light" || theme === "dark") { document.documentElement.dataset.theme = theme; } } catch (error) {} })();</script>
      <link rel="stylesheet" href="<%= AssetNames.STYLESHEET %>">
      <script defer src="<%= AssetNames.SCRIPT %>"></script>
    </head>
    <body data-view="<%= view %>" data-slug="<%= slug %>">
    <% if view != "login" %>
      <form class="logout" method="post" action="/logout"><button type="submit" aria-label="Sign out" title="Sign out"><svg class="logout-icon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M6 2.5H3.5v11H6M10 5l3 3-3 3M13 8H6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg><span class="logout-text">Sign out</span></button></form>
    <% end %>
    <%== content %>
    <% if SCRIPTED_VIEWS.include?(view) %>
      <div id="app"><p class="empty">Loading...</p></div>
    <% end %>
    </body>
    </html>
  EAG
end
