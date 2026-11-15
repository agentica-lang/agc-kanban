import Archiver from "archiver"
import Auth from "auth"
import Bond from "pkg/bond/bond"
import Cable from "cable"
import Database from "../kanban/repo/database"
import Router from "router"
import Routes from "routes"
import Users from "../kanban/users"

## The app: the cross-site check, the session, the sign-in filter, the pages and the API, the assets of `assets_dir`
## and `/cable`. A page and `/cable` need a session of the web login (a user of the database); the API takes the API
## key or, for reads and a few writes, that session. With a database, every write to the API wakes the publisher of
## the live events. `secure_cookie` marks the session cookie Secure (behind HTTPS).
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

  options = Bond.SessionOptions(
    secret: Auth.session_secret(key),
    name: Auth.cookie_name(secure_cookie),
    max_age: Users.SESSION_MS / 1000,
    secure: secure_cookie,
    same_site: "Lax",
  )

  app = (
    Bond.app()
    |> Bond.csrf()
    |> Bond.sessions(options)
    |> Bond.before(->(conn) { Auth.authorize(conn, key, pool) })
    |> Bond.after(->(conn) { wake(cable, conn) })
    |> Bond.static(Routes.ASSETS, assets_dir, ASSET_MAX_BYTES, 0, true)
    |> Router.install(pool, lease_minutes)
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
