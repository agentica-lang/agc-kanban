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

Without Docker (needs Agentica 0.31.0-alpha.1, Node and corepack):

```sh
export KANBAN_API_KEY="$(openssl rand -hex 32)"
make install assets run
```

## The web

The web view is a Vue 3 app in `app/`, built with pnpm and Vite (`make assets`; the Docker image builds it in a Node stage, and the runtime image has no Node). The build output is not in git. For a reload while you edit, run `make assets` under `entr -r`.

Open `/login` and enter the API key. The pages are view-only: boards, cards and
a live activity feed, with filters by label, agent and ready (in the URL, so a link keeps them). A card opens in a side panel (`?card=N` in the URL): each card you open is a step in the browser history, so Back and Forward walk through them. Writes go through the CLI or the API (`kanban card archive ID` hides a card for good). Behind HTTPS, set
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
| `KANBAN_API_KEY` | the one key, for the server and the CLI (at least 32 characters) |
| `KANBAN_AGENT` | name of the agent, or `--agent NAME`; required for every CLI command that acts as an agent (writes, `card next`, `card list --mine`), never taken from the config file |
| `KANBAN_BOARD` | default board slug of the CLI |
| `KANBAN_COOKIE_SECURE` | `1` to mark the web session cookie Secure (HTTPS only) |

## Tests

Run `make install` once first. The tests need Node and corepack too, because they build the web assets.

```sh
make test
```

## Install the agent skill

`skill/agc-kanban/SKILL.md` holds the rules an agent follows on the board (claim first, comment at each phase, never mark a card done). It does not repeat the commands: those are in `.agents/skills/kanban-cli/` (install the `kanban` client with `make install-cli`).

An agent with no skill installed learns the same rules from `kanban prime`; paste its output into a prompt.

Run these from the repository root. They link the skill folders (`agc-kanban` and `kanban-cli`), so a change in the repository reaches the agent:

```sh
# Claude Code: ~/.claude/skills/ (or .claude/skills/ in a project)
mkdir -p ~/.claude/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.claude/skills/agc-kanban
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.claude/skills/kanban-cli

# OpenCode: ~/.config/opencode/skills/
mkdir -p ~/.config/opencode/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.config/opencode/skills/agc-kanban
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.config/opencode/skills/kanban-cli

# Codex: ~/.agents/skills/ (or .agents/skills/ in a project)
mkdir -p ~/.agents/skills
ln -sfn "$PWD/skill/agc-kanban" ~/.agents/skills/agc-kanban
ln -sfn "$PWD/.agents/skills/kanban-cli" ~/.agents/skills/kanban-cli
```

If an agent reads only an `AGENTS.md`, add one line there: `On the kanban board, follow skill/agc-kanban/SKILL.md and run kanban prime.`

Set `KANBAN_AGENT` to a different name for each agent, and `KANBAN_BOARD` to the board slug. There is no default name: without one, a write fails with `USAGE: no agent name; ask your coordinator, then set KANBAN_AGENT or --agent` (exit 2), and the `agent` key of `config.toml` is ignored with a warning on stderr. Reads need no name.

## Install the Claude Code plugin

The repository is also a Claude Code plugin (`.claude-plugin/`): it carries the two skills and two hooks. The hooks run `hooks/board-context.sh` at the start of a session and of a subagent and add to the context the rule about the agent name and the cards in progress, at most 15 card lines in all, then "and N more". A session start lists the coordinator's own cards first, then the Doing cards of the other agents; a subagent start lists every Doing card, the coordinator's too. They only read the board.

```sh
claude plugin marketplace add agentica-lang/agc-kanban
claude plugin install agc-kanban@agc-kanban
```

The plugin needs the `kanban` client on `PATH` (`make install-cli`) and `KANBAN_URL`, `KANBAN_API_KEY` and `KANBAN_BOARD` in the environment or in the config file. Without `kanban` or without a board, the hooks print nothing; with a board that cannot be read, they print one notice. The hooks use GNU `timeout` to give up on a server that does not answer after 10 s; without it (macOS has none by default) a hung server can run past the 15 s hook timeout, and the session then gets no board context. The hooks never choose an agent name: the main agent names itself from its conversation with you, and a subagent asks its coordinator.

To try it without installing: `claude --plugin-dir /path/to/agc-kanban`. Check the manifests with `claude plugin validate .`.
