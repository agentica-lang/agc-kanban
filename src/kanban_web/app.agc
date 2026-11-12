import Auth from "auth"
import Bond from "pkg/bond/bond"
import Database from "../kanban/repo/database"
import Router from "router"

export def build(key: String, pool: Optional[Database.Pool] = none, lease_minutes: Int = 0) -> Bond.App
  (
    Bond.app()
    |> Bond.before() do |conn| Auth.authorize(conn, key) end
    |> Router.install(pool, lease_minutes)
  )
end
