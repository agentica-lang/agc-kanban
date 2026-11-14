import Archiver from "archiver"
import Auth from "auth"
import Bond from "pkg/bond/bond"
import Cable from "cable"
import Database from "../kanban/repo/database"
import Router from "router"
import Routes from "routes"

## The app: the session, the API key filter, the pages and the API, the assets of `assets_dir` and `/cable`. With a
## database, every write to the API wakes the publisher of the live events. `secure_cookie` marks the session cookie
## Secure (behind HTTPS).
def build(
  key: String,
  pool: Optional[Database.Pool] = none,
  lease_minutes: Int = 0,
  assets_dir: String = "public/assets",
  secure_cookie: Bool = false,
) -> Bond.App
  cable = Cable.start(pool)
  if pool.some?
    Archiver.start(pool.unwrap!)
  end

  secret = Auth.session_secret(key)
  app = (
    Bond.app()
    |> Bond.sessions(Bond.SessionOptions(secret: secret, name: "kanban_session", secure: secure_cookie))
    |> Bond.before(->(conn) { Auth.authorize(conn, key) })
    |> Bond.after(->(conn) { wake(cable, conn) })
    |> Bond.static(Routes.ASSETS, assets_dir, ASSET_MAX_BYTES, 0, true)
    |> Router.install(pool, lease_minutes, key)
  )

  Cable.mount(app, cable)
end

private

# The scripts and styles are small and named by their digest: a year in the cache, never revalidated.
ASSET_MAX_BYTES = 4_194_304

# After a write to the API the events are committed: nudge the publisher. A failed write nudges it too (one query
# that finds nothing); a read and a page do not.
def wake(cable: Cable.Cable, conn: Bond.Conn) -> Result[Bond.Conn]
  if conn.path.start_with?("/api/") and conn.method != "GET"
    Cable.nudge(cable)
  end

  ok(conn)
end
