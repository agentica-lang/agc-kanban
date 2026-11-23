## The pages: a shell that names the built assets, and the script draws the rest from `/api/`.

import EAG from "std/eag"
import URI from "std/uri"
import Bond from "pkg/bond/bond"
import AssetNames from "asset_names"
import Milestones from "../kanban/milestones"
import Overview from "../kanban/overview"
import Claimer from "claimer"

## The login form, with the `notes` about the last try (none show nothing) and the `username` that was typed.
def login(notes: List[String], username: String) -> String
  layout("Sign in", "login", "", login_form(notes, username))
end

## The form that creates the first user, shown while no user exists.
def register(notes: List[String], username: String) -> String
  layout("Create the first user", "login", "", register_form(notes, username))
end

## The home page: what the app is, then one card per board. It is drawn here, not by the script, so a link is a real
## link and the page needs no request after it. `now` is the time that "5 min ago" counts from.
def boards(items: List[Overview.Overview], now: Int) -> String = layout("Boards", "boards", "", home(items, now))

## The home page when the store cannot be read.
def boards_unavailable() -> String = layout("Boards", "boards", "", unavailable())

## The milestones of a board, open or closed (`state`), drawn here like the home page. `items` holds all of them, open
## ones first, and the tabs count each kind.
def milestones(slug: String, name: String, items: List[Milestones.Milestone], state: String) -> String
  layout("Milestones of #{name}", "milestones", "", milestones_list(slug, name, items, state))
end

## A page for a board that does not exist.
def board_missing() -> String = layout("Board not found", "missing", "", missing())

## The page of one board; the script reads `slug` from the page.
def board(slug: String) -> String = layout(slug, "board", slug, "")

private

# The views that the script draws (application.js): only they get `#app` and its loading text.
SCRIPTED_VIEWS = ["board"]

MINUTE = 60000
HOUR = 3600000
DAY = 86400000

def unavailable() -> String
  <<~EAG
    <main class="home">
      <h1>agc-kanban</h1>
      <p class="empty">The boards cannot be read now. Reload in a moment.</p>
    </main>
  EAG
end

def missing() -> String
  <<~EAG
    <main class="home">
      <h1>Board not found</h1>
      <p class="empty"><a href="/boards">Back to the boards</a></p>
    </main>
  EAG
end

def milestones_list(slug: String, name: String, items: List[Milestones.Milestone], state: String) -> String
  open = items.select { |item| item.state == "open" }
  closed = items.select { |item| item.state == "closed" }
  shown = open
  if state == "closed"
    shown = closed
  end

  <<~EAG
    <%@ escape &Bond.escape %>
    <main class="home">
      <header class="home-head">
        <p class="crumbs"><a href="/boards">Boards</a> / <a href="/boards/<%= slug %>"><%= name %></a></p>
        <h1>Milestones</h1>
      </header>
      <nav class="tabs" aria-label="Milestones">
        <a href="/boards/<%= slug %>/milestones"<%== current(state != "closed") %>>Open (<%= open.size %>)</a>
        <a href="/boards/<%= slug %>/milestones?state=closed"<%== current(state == "closed") %>>Closed (<%= closed.size %>)</a>
      </nav>
    <% if shown.empty? %>
      <section class="home-empty">
        <% if state == "closed" %>
        <h2>No closed milestones</h2>
        <% elsif items.empty? %>
        <h2>No milestones yet</h2>
        <% else %>
        <h2>No open milestones</h2>
        <% end %>
        <% if items.empty? %>
        <p>Flag a label as a milestone from a shell with the <code>kanban</code> client:</p>
        <pre><code>kanban milestone create 1.0.0 --due 2026-12-01 --board <%= slug %></code></pre>
        <% end %>
      </section>
    <% else %>
      <ul class="milestones">
    <% for item in shown %>
        <li class="milestone">
          <h2><a href="/boards/<%= slug %>?label=<%= URI.encode_uri_component(item.name) %>"><%= item.name %></a>
    <% if item.state == "closed" %>
            <span class="badge-closed">closed</span>
    <% end %>
          </h2>
    <% if not item.description.empty? %>
          <p class="description"><%= item.description %></p>
    <% end %>
          <div class="bar" role="img" aria-label="<%= item.percent %>% complete">
    <% if item.percent > 0 %>
            <span class="seg seg-done" style="flex-grow:<%= item.percent %>"></span>
    <% end %>
    <% if item.percent < 100 %>
            <span class="seg-rest" style="flex-grow:<%= 100 - item.percent %>"></span>
    <% end %>
          </div>
          <p class="state"><%= item.percent %>% complete · <%= item.open %> open · <%= item.closed %> closed</p>
    <% if item.due_on.some? %>
          <p class="due<%== overdue_class(item) %>">Due by <%= item.due_on.unwrap! %><%== past_due(item) %></p>
    <% end %>
        </li>
    <% end %>
      </ul>
    <% end %>
    </main>
  EAG
end

# The attribute of the tab that shows; markup of this file.
def current(on: Bool) -> String
  return " aria-current=\"page\"" if on

  ""
end

def past_due(item: Milestones.Milestone) -> String
  return " · Past due" if item.overdue

  ""
end

def overdue_class(item: Milestones.Milestone) -> String
  return " overdue" if item.overdue

  ""
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
            <span class="<%= chip_class(agent) %>" style="--hue:<%= Claimer.hue(agent) %>"><%= agent %></span>
    <% end %>
            <a class="milestones-link" href="/boards/<%= board.slug %>/milestones">Milestones</a>
            <time datetime="<%= iso_utc(board.last_activity) %>">active <%= ago(now, board.last_activity) %></time>
          </p>
        </li>
    <% end %>
      </ul>
    <% end %>
    </main>
  EAG
end

# The agent's chip: a light one takes dark text (see claimer.agc).
def chip_class(agent: String) -> String
  return "claimer light" if Claimer.light?(Claimer.hue(agent))

  "claimer"
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

## The instant of `ms` milliseconds since the Unix epoch as UTC text, to the second: `2026-10-14T19:05:42Z`.
def iso_utc(ms: Int) -> String = Time.at_us(ms * 1000).unwrap!.strftime("%Y-%m-%dT%H:%M:%SZ")

## How long ago, as the board page counts time: "just now", "5 min ago", "3 h ago", "2 d ago".
def ago(now: Int, at: Int) -> String
  elapsed = now - at
  return "just now" if elapsed < MINUTE
  return "#{elapsed / MINUTE} min ago" if elapsed < HOUR
  return "#{elapsed / HOUR} h ago" if elapsed < DAY

  "#{elapsed / DAY} d ago"
end

def login_form(notes: List[String], username: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <form class="login" method="post" action="/login">
      <h1>agc-kanban</h1>
    <%== problems(notes) %>
      <label>Username <input type="text" name="username" value="<%= username %>" autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="64" autofocus required></label>
      <label>Password <input type="password" name="password" autocomplete="current-password" required></label>
      <button type="submit">Sign in</button>
    </form>
  EAG
end

def register_form(notes: List[String], username: String) -> String
  <<~EAG
    <%@ escape &Bond.escape %>
    <form class="login" method="post" action="/register">
      <h1>agc-kanban</h1>
      <p class="hint">No user exists yet. Create the first one: it signs you in, and no one can register after it.</p>
    <%== problems(notes) %>
      <label>Username <input type="text" name="username" value="<%= username %>" autocomplete="username" autocapitalize="none" spellcheck="false" minlength="3" maxlength="32" autofocus required></label>
      <p class="hint">3 to 32 characters: letters, numbers, dots, dashes and underscores.</p>
      <label>Password <input type="password" name="password" autocomplete="new-password" required></label>
      <label>Repeat the password <input type="password" name="confirm" autocomplete="new-password" required></label>
      <p class="hint">8 to 16 characters, with an uppercase letter, a lowercase letter, a number and a special character (any that is not a letter or a number).</p>
      <button type="submit">Create the user</button>
    </form>
  EAG
end

# The notes of a refused try as a list, escaped; markup of this file.
def problems(notes: List[String]) -> String
  return "" if notes.empty?

  items = notes.map { |note| "<li>#{Bond.escape(note)}</li>" }.join("")
  "<ul class=\"notes\" role=\"alert\">#{items}</ul>"
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
