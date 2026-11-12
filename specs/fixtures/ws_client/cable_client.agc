## The browser of `cable.feature`: opens `/cable` with a cookie, subscribes to `BoardChannel` and prints every text
## frame it receives as one line, then `closed CODE` when the server ends the connection.
##
## Usage: cable_client.agc PORT COOKIE BOARD (COOKIE may be empty).

import HTTP from "std/http"
import WebSocket from "pkg/websocket-client/websocket"

PROTOCOL = "actioncable-v1-json"
# One day: the step that reads our lines has its own timeout.
FOREVER_MS = 86_400_000

def main() -> Void
  args = System.args()
  headers: List[HTTP.Header] = []
  if not args[1].empty?
    headers = [HTTP.Header(name: "Cookie", value: args[1])]
  end

  options = WebSocket.Options(headers: headers, protocols: [PROTOCOL], read_timeout_ms: FOREVER_MS)
  ws = WebSocket.connect("ws://127.0.0.1:#{args[0]}/cable", options).unwrap!
  identifier = JSON.encode(JSON.from({"channel": JSON.from("BoardChannel"), "board": JSON.from(args[2])}))
  command = JSON.from({"command": JSON.from("subscribe"), "identifier": JSON.from(identifier)})
  WebSocket.send_text(ws, JSON.encode(command)).unwrap!
  listen(ws)
end

def listen(ws: WebSocket.Client) -> Void
  while true
    case WebSocket.receive(ws)
      ok(message) ->
        case message
          WebSocket.Message.Text(text) -> say(text)

          WebSocket.Message.Close(code, _) ->
            say("closed #{code}")
            break

          WebSocket.Message.Binary(_) -> nil
        end

      error(_) ->
        say("closed 1006")
        break
    end
  end
end

def say(text: String) -> Void
  puts(text)
  IO.flush()
end
