import Auth from "auth"
import Bond from "pkg/bond/bond"
import Cable from "cable"
import Database from "../kanban/repo/database"
import Router from "router"
import Routes from "routes"

# The scripts and styles are small and named by their digest: a year in the cache, never revalidated.
ASSET_MAX_BYTES = 4_194_304

## The app: the session, the API key filter, the pages and the API, the assets of `assets_dir` and `/cable`. With a
## database, every write to the API wakes the publisher of the live events.
export def build(
  key: String,
  pool: Optional[Database.Pool] = none,
  lease_minutes: Int = 0,
  assets_dir: String = "public/assets",
) -> Bond.App
  cable = Cable.start(pool)
  secret = Auth.session_secret(key)
  app = (
    Bond.app()
    |> Bond.sessions(Bond.SessionOptions(secret: secret, name: "kanban_session"))
    |> Bond.before() do |conn| Auth.authorize(conn, key) end
    |> Bond.after() do |conn| wake(cable, conn) end
    |> Bond.static(Routes.ASSETS, assets_dir, ASSET_MAX_BYTES, 0, true)
    |> Router.install(pool, lease_minutes, key)
  )

  Cable.mount(app, cable)
end

# After a write the events are committed: nudge the publisher. A read, a failed write and a page nudge it too, which
# costs one query that finds nothing.
def wake(cable: Cable.Cable, conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path.start_with?("/api/") and conn.method != "GET"
    Cable.nudge(cable)
  end

  ok(conn)
end
