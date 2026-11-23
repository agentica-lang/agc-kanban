import Archives from "controllers/archives"
import Boards from "controllers/boards"
import Bond from "pkg/bond/bond"
import Cable from "cable"
import Cards from "controllers/cards"
import Claims from "controllers/claims"
import Columns from "controllers/columns"
import Comments from "controllers/comments"
import Database from "../kanban/repo/database"
import Deps from "controllers/deps"
import Events from "controllers/events"
import Health from "health"
import Labels from "controllers/labels"
import Milestones from "controllers/milestones"
import Pages from "controllers/pages"
import Routes from "routes"

def install(app: Bond.App, pool: Optional[Database.Pool], lease_minutes: Int, cable: Cable.Cable) -> Bond.App
  (
    app
    |> Bond.get(Routes.ROOT, &Pages.root)
    |> Bond.get(Routes.LOGIN, ->(conn) { Pages.login_form(conn, pool) })
    |> Bond.post(Routes.LOGIN, ->(conn) { Pages.login(conn, pool) })
    |> Bond.post(Routes.REGISTER, ->(conn) { Pages.register(conn, pool) })
    |> Bond.post(Routes.LOGOUT, ->(conn) { Pages.logout(conn, pool, cable) })
    |> Bond.get(Routes.BOARDS_PAGE, ->(conn) { Pages.boards(conn, pool) })
    |> Bond.get(Routes.BOARD_PAGE, ->(conn) { Pages.board(conn, pool) })
    |> Bond.get(Routes.HEALTH, ->(conn) { Health.health(conn) })
    |> Bond.get(Routes.AUTH_CHECK, ->(conn) { Health.auth_check(conn) })
    |> Bond.get(Routes.BOARDS, ->(conn) { Boards.index(conn, pool) })
    |> Bond.post(Routes.BOARDS, ->(conn) { Boards.create(conn, pool) })
    |> Bond.get(Routes.BOARD, ->(conn) { Boards.show(conn, pool) })
    |> Bond.post(Routes.CLAIM_NEXT, ->(conn) { Claims.next_card(conn, pool, lease_minutes) })
    |> Bond.get(Routes.BOARD_CARDS, ->(conn) { Cards.index(conn, pool) })
    |> Bond.get(Routes.BOARD_SEARCH, ->(conn) { Cards.search(conn, pool) })
    |> Bond.post(Routes.BOARD_CARDS, ->(conn) { Cards.create(conn, pool) })
    |> Bond.post(Routes.CARD_DEPS, ->(conn) { Deps.add(conn, pool, lease_minutes) })
    |> Bond.delete(Routes.CARD_DEP, ->(conn) { Deps.remove(conn, pool, lease_minutes) })
    |> Bond.post(Routes.CARD_RELEASE, ->(conn) { Claims.release(conn, pool) })
    |> Bond.post(Routes.CARD_MOVE, ->(conn) { Claims.move(conn, pool, lease_minutes) })
    |> Bond.post(Routes.CARD_DONE, ->(conn) { Claims.done(conn, pool) })
    |> Bond.post(Routes.CARD_ARCHIVE, ->(conn) { Claims.archive(conn, pool) })
    |> Bond.post(Routes.CARD_UNARCHIVE, ->(conn) { Archives.unarchive(conn, pool) })
    |> Bond.post(Routes.BOARD_ARCHIVE_DONE, ->(conn) { Archives.archive_done(conn, pool) })
    |> Bond.post(Routes.BOARD_AUTO_ARCHIVE, ->(conn) { Archives.auto_archive(conn, pool) })
    |> Bond.post(Routes.CARD_CLAIM, ->(conn) { Claims.claim(conn, pool, lease_minutes) })
    |> Bond.get(Routes.CARD, ->(conn) { Cards.show(conn, pool) })
    |> Bond.patch(Routes.CARD, ->(conn) { Cards.update(conn, pool, lease_minutes) })
    |> Bond.post(Routes.CARD_COMMENTS, ->(conn) { Comments.add(conn, pool, lease_minutes) })
    |> Bond.post(Routes.BOARD_COLUMNS, ->(conn) { Columns.add(conn, pool) })
    |> Bond.patch(Routes.COLUMN, ->(conn) { Columns.update(conn, pool) })
    |> Bond.delete(Routes.COLUMN, ->(conn) { Columns.remove(conn, pool) })
    |> Bond.get(Routes.BOARD_LABELS, ->(conn) { Labels.index(conn, pool) })
    |> Bond.patch(Routes.LABEL, ->(conn) { Labels.update(conn, pool) })
    |> Bond.get(Routes.BOARD_MILESTONES, ->(conn) { Milestones.index(conn, pool) })
    |> Bond.post(Routes.BOARD_MILESTONES, ->(conn) { Milestones.create(conn, pool) })
    |> Bond.patch(Routes.MILESTONE, ->(conn) { Milestones.update(conn, pool) })
    |> Bond.delete(Routes.MILESTONE, ->(conn) { Milestones.remove(conn, pool) })
    |> Bond.get(Routes.BOARD_EVENTS, ->(conn) { Events.index(conn, pool) })
  )
end
