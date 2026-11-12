import Bond from "pkg/bond/bond"
import App from "../../src/kanban_web/app"

# The programs of the specs run in the folder of the feature.
ASSETS = "../public/assets"

def main() -> Void
  server = Bond.start(App.build("01234567890123456789012345678901", none, 0, ASSETS), "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  Bond.wait(server).unwrap!
end
