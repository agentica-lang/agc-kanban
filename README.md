# agc-kanban

A shared Kanban board for coding agents. Agents use it from a CLI (`kanban`);
the owner watches it live in a read-only web page. It is written in
[Agentica](https://github.com/agentica-lang/agentica) with Bond (the HTTP
server), over SQLite. The only non-Agentica code is the small browser script.

The design is in [plan.md](plan.md).

## Run the server

With Docker (the compose file runs it at `172.28.0.10:4580` on a private
network):

```sh
cp .env.example .env   # then set KANBAN_API_KEY (openssl rand -hex 32)
make up        # docker compose up -d --build --wait
make down      # stop (the data volume stays)
```

Without Docker (needs Agentica 0.31.0, Node and corepack):

```sh
export KANBAN_API_KEY="$(openssl rand -hex 32)"
make install assets run
```

## The web

The web view is a Vue 3 app in `app/`, built with pnpm and Vite (`make assets`; the Docker image builds it in a Node stage, and the runtime image has no Node). The build output is not in git. For a reload while you edit, run `make assets` under `entr -r`.

Open `/login`. The web signs in with a username and a password; the API key is for the CLI and the API, and it does not sign in to the web. The first time, when no user exists, the login page is a form that creates the first user (a username of 3 to 32 letters, numbers, dots, dashes or underscores, and a password of 8 to 16 characters with an uppercase letter, a lowercase letter, a number and a special character): whoever opens the page first registers it and is signed in. Once a user exists, registration is closed and the page shows only the sign-in form (a user is not added from the web afterwards). After an upgrade of a server that has no user yet, register the first one at once: the first visitor of `/login` gets it. Passwords are kept as a scrypt hash with a salt; five wrong tries for one username (or thirty from one address) in five minutes lock it for the rest of the window; Sign out ends the session on the server. The pages are view-only, except for two things the owner approved: a label color (the color input beside each label in the Filters drawer) and archiving (the Archive button in a card's panel, and the Archive drawer, which archives the done cards older than N days, 3 by default, lists the archived cards and unarchives one). The session may make only these writes: `PATCH /api/labels/:id` (the color), `POST /api/cards/:id/archive` (never with `force`), `POST /api/cards/:id/unarchive` and `POST /api/boards/:board/archive-done`. The pages show boards, cards and a live activity feed, with filters by label, agent and ready, and a search box in the Filters drawer (`/` opens it; Escape clears it), all in the URL, so a link keeps them. The search ranks the cards with SQLite FTS5 and `bm25` (the title counts most) over the title, body, labels and comments; `kanban card search QUERY` and `GET /api/boards/:slug/search?q=` give the same order. A card opens in a side panel (`?card=N` in the URL): each card you open is a step in the browser history, so Back and Forward walk through them. Every other write goes through the CLI or the API (`kanban card archive ID` hides a card, `kanban card unarchive ID` brings it back, `kanban board archive-done --days 3` archives the old done cards, `kanban board auto-archive --days 7` makes the server do it every ten minutes (off by default), `kanban card list --archived` lists them). Each label of a board has a color (`kanban label list`, `kanban label update NAME --color '#rrggbb'`): a new label gets one from a GitHub-like palette, and the chips on the cards use it. Behind HTTPS, set
`KANBAN_COOKIE_SECURE=1`.

## The CLI

```sh
make install-cli    # links bin/kanban into ~/.local/bin
kanban whoami
```

Usage, commands and exit codes are in
[.agents/skills/kanban-cli/SKILL.md](.agents/skills/kanban-cli/SKILL.md).

## Configuration

| Variable | Meaning |
| --- | --- |
| `KANBAN_URL` | server URL for the CLI (default `http://127.0.0.1:4580`) |
| `KANBAN_API_KEY` | the one key, for the server and the CLI (at least 32 characters); it also signs the session cookie, so a new key signs the web out |
| `KANBAN_AGENT` | name of the agent, or `--agent NAME`; required for every CLI command that acts as an agent (writes, `card next`, `card list --mine`), never taken from the config file |
| `KANBAN_BOARD` | default board slug of the CLI |
| `KANBAN_COOKIE_SECURE` | `1` to mark the web session cookie Secure (HTTPS only), and to name it `__Host-kanban_session` |

## Tests

Run `make install` once first. The tests need Node and corepack too, because they build the web assets.

```sh
make test
```

## Install the agent skill

`skill/agc-kanban/SKILL.md` holds the rules an agent follows on the board (claim first, comment at each phase, never mark a card done). It does not repeat the commands: those are in `.agents/skills/kanban-cli/` (install the `kanban` client with `make install-cli`).

`skill/kanban-sync/SKILL.md` is a procedure for one request: sync a remote tracker (GitHub issues, Trello, ClickUp, Jira, Linear) with a board. The remote keeps the information; a card keeps the link and a few words. It is a procedure to follow on request, not a sync daemon.

An agent with no skill installed learns the same rules from `kanban prime`; paste its output into a prompt.

Run these from the repository root. They link the skill folders (`agc-kanban`, `kanban-sync` and `kanban-cli`), so a change in the repository reaches the agent:

```sh
# Claude Code: ~/.claude/skills/ (or .claude/skills/ in a project)
mkdir -p ~/.claude/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.claude/skills/agc-kanban
ln -sfn "$PWD/skill/kanban-sync" ~/.claude/skills/kanban-sync
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.claude/skills/kanban-cli

# OpenCode: ~/.config/opencode/skills/
mkdir -p ~/.config/opencode/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.config/opencode/skills/agc-kanban
ln -sfn "$PWD/skill/kanban-sync" ~/.config/opencode/skills/kanban-sync
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.config/opencode/skills/kanban-cli

# Codex: ~/.agents/skills/ (or .agents/skills/ in a project)
mkdir -p ~/.agents/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.agents/skills/agc-kanban
ln -sfn "$PWD/skill/kanban-sync" ~/.agents/skills/kanban-sync
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.agents/skills/kanban-cli
```

If an agent reads only an `AGENTS.md`, add one line there: `On the kanban board, follow skill/agc-kanban/SKILL.md and run kanban prime.` OpenCode reads the project `AGENTS.md` (searching up from the current directory) and `~/.config/opencode/AGENTS.md`; Codex reads `~/.codex/AGENTS.md` and then every `AGENTS.md` from the project root down to the current directory.

Set `KANBAN_AGENT` to a different name for each agent, and `KANBAN_BOARD` to the board slug. There is no default name: without one, a write fails with `USAGE: no agent name; ask your coordinator, then set KANBAN_AGENT or --agent` (exit 2), and the `agent` key of `config.toml` is ignored with a warning on stderr. Reads need no name.

## Install the Claude Code plugin

The repository is also a Claude Code plugin (`.claude-plugin/`): it carries the three skills and two hooks. The hooks run `hooks/board-context.sh` at the start of a session and of a subagent and add to the context the rule about the agent name and the cards in progress, at most 15 card lines in all, then "and N more". A session start lists the coordinator's own cards first, then the Doing cards of the other agents; a subagent start lists every Doing card, the coordinator's too. They only read the board.

```sh
claude plugin marketplace add agentica-lang/agc-kanban
claude plugin install agc-kanban@agc-kanban
```

The plugin needs the `kanban` client on `PATH` (`make install-cli`) and `KANBAN_URL`, `KANBAN_API_KEY` and `KANBAN_BOARD` in the environment or in the config file. Without `kanban` or without a board, the hooks print nothing; with a board that cannot be read, they print one notice. The hooks use GNU `timeout` to give up on a server that does not answer after 10 s; without it (macOS has none by default) a hung server can run past the 15 s hook timeout, and the session then gets no board context. The hooks never choose an agent name: the main agent names itself from its conversation with you, and a subagent asks its coordinator.

To try it without installing: `claude --plugin-dir /path/to/agc-kanban`. Check the manifests with `claude plugin validate .`.

## Install for OpenCode

OpenCode reads a skill folder (a directory with a `SKILL.md`) from `~/.config/opencode/skills/` and `.opencode/skills/`, and also from `~/.claude/skills/`, `~/.agents/skills/`, `.claude/skills/` and `.agents/skills/` (project folders are searched from the current directory up to the project root). The links of the section above therefore work: either the OpenCode block, or the Claude Code or Codex one. Its docs: [skills](https://opencode.ai/docs/skills/) and [rules](https://opencode.ai/docs/rules/).

There is no session hook to install. OpenCode's plugin documentation ([plugins](https://opencode.ai/docs/plugins/), [server plugins](https://opencode.ai/docs/build/plugins/server/)) lists no session-start or subagent-start hook, and this repository ships no OpenCode plugin. Do it by hand instead: put the `AGENTS.md` line above in the project (or in `~/.config/opencode/AGENTS.md`), and start a session with the output of `kanban prime`, or tell the agent to run it. A subagent needs its name in its brief (`KANBAN_AGENT`).

## Install for Codex

Codex reads a skill folder from `.agents/skills/` (in the current directory, the folder above it and the repository root), `~/.agents/skills/` and `/etc/codex/skills`, and it follows symlinks, so the Codex block above is enough. Each `SKILL.md` needs `name` and `description`, which all the skills have. Docs: [skills](https://learn.chatgpt.com/docs/build-skills) and [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Codex has [hooks](https://learn.chatgpt.com/docs/hooks), including `SessionStart` and `SubagentStart`, and the text a hook prints is added to the context. `hooks/board-context.sh` prints the `hookSpecificOutput.additionalContext` JSON that the Codex page documents for both events, so the plugin script works there. This repository has no Codex plugin, so add the two hooks to `~/.codex/hooks.json` (or `<repo>/.codex/hooks.json`) with the path of your clone:

```json
{
  "hooks": {
    "SessionStart": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/agc-kanban/hooks/board-context.sh session", "timeout": 15}]}
    ],
    "SubagentStart": [
      {"matcher": "*", "hooks": [{"type": "command", "command": "/path/to/agc-kanban/hooks/board-context.sh subagent", "timeout": 15}]}
    ]
  }
}
```

The `timeout` is in seconds. Codex asks you to review and trust a new hook before it runs (`/hooks` in the CLI). The same needs as for Claude Code hold: `kanban` on `PATH`, and `KANBAN_URL`, `KANBAN_API_KEY` and `KANBAN_BOARD` in the environment or the config file. The specs of the script run it on its own, not inside Codex. Without the hooks, run `kanban prime` at the start of a session.
