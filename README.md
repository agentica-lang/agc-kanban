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

Without Docker (needs Agentica 0.30.1, Node and corepack):

```sh
export KANBAN_API_KEY="$(openssl rand -hex 32)"
make install assets run
```

## The web

Open `/login` and enter the API key. The pages are view-only: boards, cards and
a live activity feed. Writes go through the CLI or the API. Behind HTTPS, set
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
| `KANBAN_AGENT` | name of the agent, required for CLI writes |
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

Set `KANBAN_AGENT` to a different name for each agent, and `KANBAN_BOARD` to the board slug.
