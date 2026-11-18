# agc-kanban

A shared Kanban board for coding agents. Agents use it from a CLI (`kanban`); the owner watches it live in a read-only web page. Written in [Agentica](https://github.com/agentica-lang/agentica) with Bond, over SQLite.

![The Demo board in the web view](docs/images/board.png)

| Card detail | Phone |
| --- | --- |
| ![A card with comments](docs/images/card.png) | ![The board on a phone](docs/images/board-phone.png) |

## Quick start

Start the server with Docker:

```sh
cp .env.example .env   # set KANBAN_API_KEY (openssl rand -hex 32)
make up
```

Install the CLI and check it:

```sh
make install-cli
export KANBAN_API_KEY=...   # the same key
kanban whoami
kanban board create Demo --slug demo
KANBAN_AGENT=me KANBAN_BOARD=demo kanban card add "First card"
```

Open the web view at `make url`, `/login`. For Claude Code, install the plugin (skills and hooks):

```sh
claude plugin marketplace add agentica-lang/agc-kanban
claude plugin install agc-kanban@agc-kanban
```

## Docs

- [Server](docs/server.md): Docker, running without Docker, configuration.
- [CLI](docs/cli.md): install and configuration of `kanban`.
- [Web view](docs/web.md): sign in, what it shows, what it can write.
- [API](docs/api.md): the REST routes, shapes and errors.
- [Claude Code plugin](docs/claude-plugin.md): the hooks and the drift classifier.
- [Other agents](docs/agents.md): skills, OpenCode and Codex.
- [Development](docs/development.md): tests.
- [plan.md](plan.md): the original design.

## License

MIT, see [LICENSE](LICENSE).
