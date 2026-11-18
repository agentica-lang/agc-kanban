# CLI

```sh
make install-cli    # links bin/kanban into ~/.local/bin
kanban whoami
```

Commands, flags and exit codes are in
[.agents/skills/kanban-cli/SKILL.md](../.agents/skills/kanban-cli/SKILL.md), and `kanban` with no arguments prints the list.

## Configuration

| Variable | Meaning |
| --- | --- |
| `KANBAN_URL` | server URL (default `http://127.0.0.1:4580`) |
| `KANBAN_API_KEY` | the server's key; see [server.md](server.md) |
| `KANBAN_AGENT` | name of the agent, or `--agent NAME`; required for every command that acts as an agent (writes, `card next`, `card list --mine`), never taken from the config file |
| `KANBAN_BOARD` | default board slug |

Set `KANBAN_AGENT` to a different name for each agent. There is no default name: without one, a write fails with `USAGE: no agent name; ask your coordinator, then set KANBAN_AGENT or --agent` (exit 2), and the `agent` key of `config.toml` is ignored with a warning on stderr. Reads need no name.
