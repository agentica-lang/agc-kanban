import Bond from "pkg/bond/bond"
import App from "src/kanban_web/app"

def main() -> Void
  key = System.env("KANBAN_API_KEY").unwrap_or("")
  if key.length < 32
    IO.warn("KANBAN_API_KEY must be at least 32 characters")
    System.exit(1)
  end

  host = System.env("KANBAN_HOST").unwrap_or("127.0.0.1")
  port = System.env("KANBAN_PORT").unwrap_or("4580").to_i()
  if not port.ok?
    IO.warn("invalid KANBAN_PORT")
    System.exit(1)
  end

  result = Bond.run(App.build(key), host, port.unwrap!)
  if not result.ok?
    IO.warn(result.message)
    System.exit(1)
  end
end
