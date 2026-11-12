import Bond from "pkg/bond/bond"

# A server from before card links: it takes any card update and answers the card without a `links` field.
CARD = (
  "{\"card\":{\"id\":1,\"board\":\"project\",\"column\":\"Todo\",\"column_id\":1,\"position\":0,\"title\":\"Old\",\"body\":\"\",\"labels\":[],\"priority\":2,\"claimed_by\":null,\"claimed_at\":null,\"lease_until\":null,\"branch\":null,\"worktree\":null,\"depends_on\":[],\"blocks\":[],\"ready\":true,\"done\":false,\"created_by\":\"agent-1\",\"created_at\":1,\"updated_at\":1,\"done_at\":null,\"version\":2}}"
)

def main() -> Void
  app = Bond.patch(Bond.app(), "/api/cards/:id", &card)
  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts(Bond.local_port(server).to_s)
  IO.flush()
  Bond.wait(server).unwrap!
end

def card(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.json(conn, 200, JSON.parse(CARD).unwrap!))
