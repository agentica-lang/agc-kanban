## The pages: a shell that names the built assets, and the script draws the rest from `/api/`.

import EAG from "std/eag"
import Bond from "pkg/bond/bond"
import UTC from "std/utc"
import AssetNames from "asset_names"
import Overview from "../kanban/overview"

# The views that the script draws (application.js): only they get `#app` and its loading text.
SCRIPTED_VIEWS = ["board"]

MINUTE = 60000
HOUR = 3600000
DAY = 86400000

## The login form, with a `note` about the last try ("" shows none).
export def login(note: String) -> String = layout("Sign in", "login", "", form(note))

## The home page: what the app is, then one card per board. It is drawn here, not by the script, so a link is a real
## link and the page needs no request after it. `now` is the time that "5 min ago" counts from.
export def boards(items: List[Overview.Overview], now: Int) -> String
  layout("Boards", "boards", "", home(items, now))
end

## The home page when the store cannot be read.
export def boards_unavailable() -> String = layout("Boards", "boards", "", unavailable())

## The page of one board; the script reads `slug` from the page.
export def board(slug: String) -> String = layout(slug, "board", slug, "")

def unavailable() -> String
  <<~EAG
    <main class="home">
      <h1>agc-kanban</h1>
      <p class="empty">The boards cannot be read now. Reload in a moment.</p>
    </main>
  EAG
end

def home(items: List[Overview.Overview], now: Int) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <main class="home">
      <header class="home-head">
        <h1>agc-kanban</h1>
        <p class="lede">A shared Kanban board for coding agents. Agents work through the <code>kanban</code> client; this view is read-only: open a board to watch cards move as they work.</p>
      </header>
    <% if items.empty? %>
      <section class="home-empty">
        <h2>No boards yet</h2>
        <p>Create the first one from a shell with the <code>kanban</code> client:</p>
        <pre><code>export KANBAN_AGENT=me
    kanban board create "Project" --slug project</code></pre>
      </section>
    <% else %>
      <p class="summary"><%= summary(items) %></p>
      <ul class="boards">
    <% for board in items %>
        <li class="board-card">
          <h2><a class="board-link" href="/boards/<%= board.slug %>"><%= board.name %></a></h2>
          <p class="slug"><%= board.slug %></p>
    <% if total(board) == 0 %>
          <p class="state">No cards yet</p>
    <% else %>
          <div class="bar" aria-hidden="true">
    <% for column in board.columns %>
    <% if column.cards > 0 %>
            <span class="<%= segment_class(column) %>" style="flex-grow:<%= column.cards %>"></span>
    <% end %>
    <% end %>
          </div>
          <p class="state"><%= state(board) %></p>
    <% end %>
          <ul class="counts">
    <% for column in board.columns %>
            <li><b><%= column.cards %></b> <span><%= column.name %></span></li>
    <% end %>
          </ul>
          <p class="facts">
    <% if board.blocked > 0 %>
            <span class="blocked"><%= board.blocked %> blocked</span>
    <% end %>
    <% for agent in board.agents %>
            <span class="claimer" style="--hue:<%= hue(agent) %>"><%= agent %></span>
    <% end %>
            <time datetime="<%= UTC.iso8601(board.last_activity) %>">active <%= ago(now, board.last_activity) %></time>
          </p>
        </li>
    <% end %>
      </ul>
    <% end %>
    </main>
  EAG
end

def segment_class(column: Overview.ColumnCount) -> String
  return "seg seg-done" if column.done

  "seg"
end

def total(board: Overview.Overview) -> Int = board.columns.map { |column| column.cards }.sum

def done_count(board: Overview.Overview) -> Int
  board.columns.select { |column| column.done }.map { |column| column.cards }.sum
end

# The open cards are the ones outside the done column.
def state(board: Overview.Overview) -> String
  open = total(board) - done_count(board)
  return "All done" if open == 0

  "#{open} open of #{total(board)}"
end

def summary(items: List[Overview.Overview]) -> String
  open = items.map { |board| total(board) - done_count(board) }.sum
  names = items.flat_map { |board| board.agents }.uniq
  "#{plural(items.size, "board")} · #{open} open · #{plural(names.size, "agent")} working"
end

def plural(count: Int, word: String) -> String
  return "#{count} #{word}" if count == 1

  "#{count} #{word}s"
end

## How long ago, as the board page counts time: "just now", "5 min ago", "3 h ago", "2 d ago".
def ago(now: Int, at: Int) -> String
  elapsed = now - at
  return "just now" if elapsed < MINUTE
  return "#{elapsed / MINUTE} min ago" if elapsed < HOUR
  return "#{elapsed / HOUR} h ago" if elapsed < DAY

  "#{elapsed / DAY} d ago"
end

# The color of an agent from its name, as Card.vue picks it, so an agent keeps one color on both pages.
def hue(name: String) -> Int
  sum = 0
  for char in name.split("")
    sum = (sum * 31 + char.code) % 360
  end

  sum
end

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
