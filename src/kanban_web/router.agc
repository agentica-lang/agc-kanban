import Boards from "controllers/boards"
import Bond from "pkg/bond/bond"
import Cards from "controllers/cards"
import Claims from "controllers/claims"
import Columns from "controllers/columns"
import Comments from "controllers/comments"
import Database from "../kanban/repo/database"
import Deps from "controllers/deps"
import Events from "controllers/events"
import Health from "health"
import Routes from "routes"

export def install(app: Bond.App, pool: Optional[Database.Pool], lease_minutes: Int) -> Bond.App
  (
    app
    |> Bond.get(Routes.HEALTH) do |conn| Health.health(conn) end
    |> Bond.get(Routes.AUTH_CHECK) do |conn| Health.auth_check(conn) end
    |> Bond.get(Routes.BOARDS) do |conn| Boards.index(conn, pool) end
    |> Bond.post(Routes.BOARDS) do |conn| Boards.create(conn, pool) end
    |> Bond.get(Routes.BOARD) do |conn| Boards.show(conn, pool) end
    |> Bond.post(Routes.CLAIM_NEXT) do |conn| Claims.next_card(conn, pool, lease_minutes) end
    |> Bond.get(Routes.BOARD_CARDS) do |conn| Cards.index(conn, pool) end
    |> Bond.post(Routes.BOARD_CARDS) do |conn| Cards.create(conn, pool) end
    |> Bond.post(Routes.CARD_DEPS) do |conn| Deps.add(conn, pool, lease_minutes) end
    |> Bond.delete(Routes.CARD_DEP) do |conn| Deps.remove(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_RELEASE) do |conn| Claims.release(conn, pool) end
    |> Bond.post(Routes.CARD_MOVE) do |conn| Claims.move(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_DONE) do |conn| Claims.done(conn, pool) end
    |> Bond.post(Routes.CARD_CLAIM) do |conn| Claims.claim(conn, pool, lease_minutes) end
    |> Bond.get(Routes.CARD) do |conn| Cards.show(conn, pool) end
    |> Bond.patch(Routes.CARD) do |conn| Cards.update(conn, pool, lease_minutes) end
    |> Bond.post(Routes.CARD_COMMENTS) do |conn| Comments.add(conn, pool, lease_minutes) end
    |> Bond.post(Routes.BOARD_COLUMNS) do |conn| Columns.add(conn, pool) end
    |> Bond.patch(Routes.COLUMN) do |conn| Columns.update(conn, pool) end
    |> Bond.delete(Routes.COLUMN) do |conn| Columns.remove(conn, pool) end
    |> Bond.get(Routes.BOARD_EVENTS) do |conn| Events.index(conn, pool) end
  )
end
