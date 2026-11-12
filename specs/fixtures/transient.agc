import Bond from "pkg/bond/bond"
import App from "../../src/kanban_web/app"

def main() -> Void
  listener = TCP.listen("127.0.0.1", 0).unwrap!
  port = TCP.local_port(listener)
  puts(port.to_s)
  IO.flush()
  socket = TCP.accept(listener, 30000).unwrap!
  TCP.close(socket)
  TCP.close_listener(listener)
  server = Bond.start(App.build("01234567890123456789012345678901"), "127.0.0.1", port).unwrap!
  Bond.wait(server).unwrap!
end
