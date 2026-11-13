import Boards from "../../kanban/boards"
import Bond from "pkg/bond/bond"
import Columns from "../../kanban/columns"
import Database from "../../kanban/repo/database"
import Failure from "../failure"

def add(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, CreateColumn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Columns.Add(
    board: Bond.param(conn, "board").unwrap_or(""),
    name: data.name,
    position: data.position,
    done: data.done.unwrap_or(false),
    wip_limit: data.wip_limit,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
  )

  result = Columns.add(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 201, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def update(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  body = Bond.body_text(conn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not body.ok?

  decoded = JSON.decode(body.unwrap!, UpdateColumn)
  return ok(Failure.reject(conn, 400, "INVALID", "invalid body", some("body"))) if not decoded.ok?

  data = decoded.unwrap!
  input = Columns.Update(
    id: id.unwrap!,
    name: data.name,
    position: data.position,
    done: data.done,
    wip_limit: data.wip_limit,
    actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""),
    force: data.force.unwrap_or(false),
  )

  result = Columns.update(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.json_as(conn, 200, ColumnAnswer.codec, ColumnAnswer(column: result.unwrap!)))
end

def remove(conn: Bond.Conn, pool: Optional[Database.Pool]) -> Result[Bond.Conn]
  return ok(Failure.reject(conn, 503, "BUSY", "database unavailable")) if not pool.some?

  id = Bond.param_int(conn, "id")
  return ok(Failure.reject(conn, 400, "INVALID", "invalid id", some("id"))) if not id.ok?

  input = Columns.Remove(id: id.unwrap!, actor: Bond.request_header(conn, "X-Kanban-Agent").unwrap_or(""))
  result = Columns.remove(pool.unwrap!, input)
  return ok(Failure.answer(conn, result.message)) if not result.ok?

  ok(Bond.status(conn, 204))
end

private

struct CreateColumn
  name: String
  position: Optional[Int]
  done: Optional[Bool]
  wip_limit: Optional[Int]
end

struct UpdateColumn
  force: Optional[Bool]
  name: Optional[String]
  position: Optional[Int]
  done: Optional[Bool]
  wip_limit: Optional[Int]
end

struct ColumnAnswer
  column: Boards.Column
end
