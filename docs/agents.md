# Install for agents

The Claude Code plugin ([claude-plugin.md](claude-plugin.md)) carries the skills and hooks for Claude Code. For the rest, link the skills by hand.

## Skills

`skill/agc-kanban/SKILL.md` holds the rules an agent follows on the board (claim first, comment at each phase, never mark a card done). It does not repeat the commands: those are in `.agents/skills/kanban-cli/` (install the `kanban` client with `make install-cli`, see [cli.md](cli.md)).

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

Set `KANBAN_AGENT` (a different name for each agent) and `KANBAN_BOARD`; see [cli.md](cli.md).

## OpenCode

OpenCode reads a skill folder (a directory with a `SKILL.md`) from `~/.config/opencode/skills/` and `.opencode/skills/`, and also from `~/.claude/skills/`, `~/.agents/skills/`, `.claude/skills/` and `.agents/skills/` (project folders are searched from the current directory up to the project root). The links of the skills section above therefore work: either the OpenCode block, or the Claude Code or Codex one. Its docs: [skills](https://opencode.ai/docs/skills/) and [rules](https://opencode.ai/docs/rules/).

There is no session hook to install. OpenCode's plugin documentation ([plugins](https://opencode.ai/docs/plugins/), [server plugins](https://opencode.ai/docs/build/plugins/server/)) lists no session-start or subagent-start hook, and this repository ships no OpenCode plugin. Do it by hand instead: put the `AGENTS.md` line above in the project (or in `~/.config/opencode/AGENTS.md`), and start a session with the output of `kanban prime`, or tell the agent to run it. A subagent needs its name in its brief (`KANBAN_AGENT`).

## Codex

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

The `timeout` is in seconds. Codex asks you to review and trust a new hook before it runs (`/hooks` in the CLI). The needs are the plugin's: see [claude-plugin.md](claude-plugin.md). The specs of the script run it on its own, not inside Codex. Without the hooks, run `kanban prime` at the start of a session.
