import Settings from "../src/kanban_cli/settings"

def test_flag_then_environment_then_file_then_default() -> Result[Void]
  plain = Settings.Flags(url: none, agent: none, board: none, json: false)
  env = {
    "KANBAN_URL": "http://env:1",
    "KANBAN_API_KEY": "env-key",
    "KANBAN_AGENT": "env-agent",
    "KANBAN_BOARD": "env-board",
  }

  file = {"url": "http://file:1", "api_key": "file-key", "agent": "file-agent", "board": "file-board"}
  try Test.eq(
    Settings.resolve(plain, {}, file),
    Settings.Config(url: "http://file:1", key: "file-key", agent: "file-agent", board: "file-board", json: false),
  )

  try Test.eq(
    Settings.resolve(plain, env, file),
    Settings.Config(url: "http://env:1", key: "env-key", agent: "env-agent", board: "env-board", json: false),
  )

  flags = Settings.Flags(url: some("http://flag:1"), agent: some("flag-agent"), board: some("flag-board"), json: true)
  try Test.eq(
    Settings.resolve(flags, env, file),
    Settings.Config(url: "http://flag:1", key: "env-key", agent: "flag-agent", board: "flag-board", json: true),
  )

  try Test.eq(
    Settings.resolve(plain, {}, {}),
    Settings.Config(url: "http://127.0.0.1:4580", key: "", agent: "", board: "", json: false),
  )

  ok()
end
