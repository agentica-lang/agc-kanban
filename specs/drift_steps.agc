## The steps of `doctor.feature` and `drift_hooks.feature`: `kanban doctor` and the drift hooks of the plugin, run
## against the database server with a fake `gh` and a fake `claude` first on PATH (`fixtures/hook_bin/`). The hooks
## run `kanban` through the stub of `fixtures/plugin_bin/`, so they drive the CLI source of this checkout.

import BDD from "std/bdd"
import HTTP from "std/http"

KEY = "01234567890123456789012345678901"

def steps() -> List[BDD.Step]
  [
    BDD.step("a card {string} is in {string} held by {string} with the link {string}", &seed_card),
    BDD.step("I run kanban doctor {string} while gh says {string}", &run_doctor),
    BDD.step("agent {string} sets the branch of card {int} to {string}", &set_branch),
    BDD.step("the fake claude answers {string}", &fake_claude_answers),
    BDD.step("the hook queue has {string}", &queue_has),
    BDD.step("I run the prompt-submit hook as agent {string} with a doctor that hangs", &prompt_submit_hung),
    BDD.step("the hung doctor and its child are gone", &hung_gone),
    BDD.step(
      "I run the subagent-stop hook for a transcript that starts with {string}, runs {string} and hands back {string}",
      &subagent_handback,
    ),
    BDD.step(
      "I run the post-tool hook as agent {string} for the command {string} with the output {string}",
      &post_tool,
    ),
    BDD.step(
      "I run the post-tool hook inside a subagent for the command {string} with the output {string}",
      &post_tool_subagent,
    ),
    BDD.step("I run the prompt-submit hook as agent {string}", &prompt_submit),
    BDD.step(
      "I run the subagent-stop hook for a transcript that starts with {string} and ends with {string}",
      &subagent_stop,
    ),
    BDD.step("the fake claude was run with {string}", &claude_ran_with),
    BDD.step("the fake claude was not run", &claude_not_run),
    BDD.step("the gh log has {int} calls", &gh_calls),
    BDD.step("the hook queue is empty", &queue_empty),
    BDD.step("the hook queue contains {string}", &queue_contains),
  ]
end

def port_of(ctx: BDD.Context) -> Int = JSON.int(BDD.get(ctx, "port").unwrap!).unwrap!

def data_dir(ctx: BDD.Context) -> String = JSON.string(BDD.get(ctx, "data_dir").unwrap!).unwrap!

def cache_dir(ctx: BDD.Context) -> String = "#{data_dir(ctx)}/hook-cache"

def gh_log(ctx: BDD.Context) -> String = "#{data_dir(ctx)}/gh.log"

def claude_log(ctx: BDD.Context) -> String = "#{data_dir(ctx)}/claude.log"

def call(ctx: BDD.Context, agent: String, method: String, path: String, body: String) -> HTTP.Response
  headers = [
    HTTP.Header(name: "apikey", value: KEY),
    HTTP.Header(name: "X-Kanban-Agent", value: agent),
    HTTP.Header(name: "Content-Type", value: "application/json"),
  ]

  client = HTTP.client().unwrap!
  response = HTTP.request(client, method, "http://127.0.0.1:#{port_of(ctx)}#{path}", body.bytes, headers).unwrap!
  HTTP.close_client(client)
  response
end

def seed_card(ctx: BDD.Context, args: List[String]) -> BDD.Context
  fields: Map[String, JSON.Value] = {"title": JSON.from("Card in #{args[1]}")}
  if not args[3].empty?
    fields = fields.put("links", JSON.from([args[3]]))
  end

  created = call(ctx, "agent-1", "POST", "/api/boards/project/cards", JSON.encode(JSON.object(fields)))
  document = JSON.parse(HTTP.text(created.body, created.headers).unwrap!).unwrap!
  id = JSON.int(JSON.get(JSON.get(document, "card").unwrap!, "id").unwrap!).unwrap!
  mover = "agent-1"
  if not args[2].empty?
    mover = args[2]
    _ = call(ctx, mover, "POST", "/api/cards/#{id}/claim", "{}")
  end

  moved = call(ctx, mover, "POST", "/api/cards/#{id}/move", JSON.encode(JSON.from({"column": args[1]})))
  BDD.assert(ctx, moved.status == 200, "move to #{args[1]} failed with #{moved.status}")
end

# The same keys as `I run kanban`, so its Then steps read the result.
def record(ctx: BDD.Context, process: Process) -> BDD.Context
  code = Process.wait(process, 90000).unwrap!
  output = Process.output(process, 30000).unwrap!
  Process.close(process)
  stored = BDD.set(ctx, "kanban_exit", JSON.from(code))
  with_out = BDD.set(stored, "kanban_output", JSON.from("#{output.stdout}#{output.stderr}"))
  with_err = BDD.set(with_out, "kanban_stdout", JSON.from(output.stdout))
  BDD.set(with_err, "kanban_stderr", JSON.from(output.stderr))
end

def base_env(ctx: BDD.Context) -> Map[String, String]
  here = Path.cwd().unwrap!
  path = (
    "#{here}/specs/fixtures/hook_bin:#{here}/specs/fixtures/plugin_bin:#{System.env("PATH").unwrap_or("/usr/bin:/bin")}"
  )

  {
    "KANBAN_URL": "http://127.0.0.1:#{port_of(ctx)}",
    "KANBAN_API_KEY": KEY,
    "KANBAN_BOARD": "project",
    "KANBAN_AGENT": "",
    "PATH": path,
    "XDG_CACHE_HOME": cache_dir(ctx),
    "FAKE_GH_LOG": gh_log(ctx),
    "FAKE_CLAUDE_LOG": claude_log(ctx),
  }
end

def run_doctor(ctx: BDD.Context, args: List[String]) -> BDD.Context
  env = base_env(ctx).put("FAKE_GH_STATE", args[1])
  if args[1] == "fail"
    env = env.put("FAKE_GH_FAIL", "1")
  end

  words = ["cli.agc", "doctor"] + args[0].split(" ").select do |word| not word.empty? end
  record(ctx, Process.spawn_captured("agentica", words, Process.Options(env: env)).unwrap!)
end

def fake_claude_answers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  BDD.set(ctx, "fake_claude", JSON.from(args[0]))
end

def run_hook(ctx: BDD.Context, mode: String, agent: String, input: JSON.Value) -> BDD.Context
  env = base_env(ctx).put("KANBAN_AGENT", agent)
  reply = BDD.get(ctx, "fake_claude")
  if reply.ok?
    env = env.put("FAKE_CLAUDE_REPLY", JSON.string(reply.unwrap!).unwrap!)
  end

  process = Process.spawn_captured("hooks/drift.sh", [mode], Process.Options(env: env)).unwrap!
  Process.send(process, JSON.encode(input), 30000).unwrap!
  Process.close_stdin(process, 30000).unwrap!
  record(ctx, process)
end

def bash_input(command: String, output: String) -> Map[String, JSON.Value]
  {
    "hook_event_name": JSON.from("PostToolUse"),
    "tool_name": JSON.from("Bash"),
    "tool_input": JSON.object({"command": JSON.from(command)}),
    "tool_response": JSON.object({"stdout": JSON.from(output), "stderr": JSON.from("")}),
    "cwd": JSON.from(Path.cwd().unwrap!),
  }
end

def post_tool(ctx: BDD.Context, args: List[String]) -> BDD.Context
  run_hook(ctx, "post-tool", args[0], JSON.object(bash_input(args[1], args[2])))
end

def post_tool_subagent(ctx: BDD.Context, args: List[String]) -> BDD.Context
  input = bash_input(args[0], args[1]).put("agent_id", JSON.from("a1"))
  run_hook(ctx, "post-tool", "coordinator", JSON.object(input))
end

def prompt_submit(ctx: BDD.Context, args: List[String]) -> BDD.Context
  run_hook(
    ctx,
    "prompt-submit",
    args[0],
    JSON.object({"hook_event_name": JSON.from("UserPromptSubmit"), "prompt": JSON.from("hi")}),
  )
end

def line_of(kind: String, content: JSON.Value) -> String
  message = JSON.object({"role": JSON.from(kind), "content": content})
  JSON.encode(JSON.object({"type": JSON.from(kind), "message": message}))
end

def user_line(text: String) -> String = line_of("user", JSON.from(text))

def assistant_line(text: String) -> String
  line_of("assistant", JSON.array([JSON.object({"type": JSON.from("text"), "text": JSON.from(text)})]))
end

def subagent_stop(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = "#{data_dir(ctx)}/agent.jsonl"
  File.write_text(path, "#{user_line(args[0])}\n#{assistant_line(args[1])}\n").unwrap!
  input = {
    "hook_event_name": JSON.from("SubagentStop"),
    "agent_id": JSON.from("a1"),
    "agent_type": JSON.from("general-purpose"),
    "agent_transcript_path": JSON.from(path),
    "last_assistant_message": JSON.from(args[1]),
  }

  run_hook(ctx, "subagent-stop", "coordinator", JSON.object(input))
end

def read_or_empty(path: String) -> String = File.read_text(path).unwrap_or("")

def claude_ran_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  log = read_or_empty(claude_log(ctx))
  BDD.assert(ctx, log.include?(args[0]), "claude log was #{log}")
end

def claude_not_run(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  log = read_or_empty(claude_log(ctx))
  BDD.assert(ctx, log.empty?, "claude log was #{log}")
end

def gh_calls(ctx: BDD.Context, args: List[String]) -> BDD.Context
  lines = read_or_empty(gh_log(ctx)).split("\n").select do |line| not line.empty? end
  BDD.assert(ctx, lines.size == args[0].to_i!, "gh was called #{lines.size} times")
end

def queue_text(ctx: BDD.Context) -> String = read_or_empty("#{cache_dir(ctx)}/agc-kanban/queue-project.txt")

def queue_empty(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  BDD.assert(ctx, queue_text(ctx).empty?, "queue was #{queue_text(ctx)}")
end

def queue_contains(ctx: BDD.Context, args: List[String]) -> BDD.Context
  BDD.assert(ctx, queue_text(ctx).include?(args[0]), "queue was #{queue_text(ctx)}")
end

def set_branch(ctx: BDD.Context, args: List[String]) -> BDD.Context
  body = JSON.encode(JSON.from({"branch": args[2]}))
  changed = call(ctx, args[0], "PATCH", "/api/cards/#{args[1]}", body)
  BDD.assert(ctx, changed.status == 200, "branch update failed with #{changed.status}")
end

def queue_has(ctx: BDD.Context, args: List[String]) -> BDD.Context
  _ = Dir.mkdir(cache_dir(ctx))
  _ = Dir.mkdir("#{cache_dir(ctx)}/agc-kanban")
  File.write_text("#{cache_dir(ctx)}/agc-kanban/queue-project.txt", "#{args[0]}\n").unwrap!
  ctx
end

def pid_file(ctx: BDD.Context) -> String = "#{data_dir(ctx)}/doctor.pid"

# The doctor of the hook sleeps for 30 s; the hook gives up after 1 s.
def prompt_submit_hung(ctx: BDD.Context, args: List[String]) -> BDD.Context
  here = Path.cwd().unwrap!
  env = (
    base_env(ctx)
      .put("KANBAN_AGENT", args[0])
      .put("KANBAN_DOCTOR_TIMEOUT", "1")
      .put("FAKE_PID_FILE", pid_file(ctx))
  )

  env = env.put("PATH", "#{here}/specs/fixtures/slow_bin:#{env.get("PATH").unwrap!}")
  process = Process.spawn_captured("hooks/drift.sh", ["prompt-submit"], Process.Options(env: env)).unwrap!
  Process.send(process, "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}", 30000).unwrap!
  Process.close_stdin(process, 30000).unwrap!
  record(ctx, process)
end

# Linux: field 3 of /proc/PID/stat is the state; a gone process has none and a killed one waiting to be reaped is Z.
def hung_gone(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  pid = read_or_empty(pid_file(ctx)).strip
  script = "s=$(cut -d' ' -f3 /proc/$1/stat 2>/dev/null); [ \"$s\" != S ] && [ \"$s\" != R ]"
  process = Process.spawn_captured("sh", ["-c", script, "sh", pid]).unwrap!
  code = Process.wait(process, 10000).unwrap!
  Process.close(process)
  BDD.assert(ctx, not pid.empty? and code == 0, "the child #{pid} of the doctor is still running")
end

def tool_line(name: String, input: Map[String, JSON.Value]) -> String
  line_of(
    "assistant",
    JSON.array([JSON.object({"type": JSON.from("tool_use"), "name": JSON.from(name), "input": JSON.object(input)})]),
  )
end

def subagent_handback(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = "#{data_dir(ctx)}/agent.jsonl"
  lines = [
    user_line(args[0]),
    tool_line("Bash", {"command": JSON.from(args[1])}),
    tool_line("SubagentHandback", {"message": JSON.from(args[2])}),
    assistant_line("ok"),
  ]

  File.write_text(path, "#{lines.join("\n")}\n").unwrap!
  input = {
    "hook_event_name": JSON.from("SubagentStop"),
    "agent_id": JSON.from("a1"),
    "agent_transcript_path": JSON.from(path),
    "last_assistant_message": JSON.from("ok"),
  }

  run_hook(ctx, "subagent-stop", "coordinator", JSON.object(input))
end
