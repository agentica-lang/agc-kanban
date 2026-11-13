import Bond from "pkg/bond/bond"
import Database from "../kanban/repo/database"

def reject(conn: Bond.Conn, status: Int, code: String, message: String, field: Optional[String] = none) -> Bond.Conn
  Bond.json_as(
    conn,
    status,
    ErrorAnswer.codec,
    ErrorAnswer(error: ApiError(code: code, message: message, field: field)),
  ).with(halted: true)
end

def answer(conn: Bond.Conn, message: String, card_id: Optional[Int] = none) -> Bond.Conn
  if message.start_with?("INVALID:")
    return reject(conn, 400, "INVALID", message, some(message.slice(8, message.length - 8)))
  end

  if message.start_with?("CLAIMED:")
    holder = message.slice(8, message.length - 8)
    answer = ClaimedAnswer(
      error: ClaimedError(
        code: "CLAIMED",
        message: "card is claimed",
        card_id: card_id.unwrap_or(0),
        claimed_by: holder,
      ),
    )

    return Bond.json_as(conn, 409, ClaimedAnswer.codec, answer).with(halted: true)
  end

  if message.start_with?("BLOCKED:")
    ids = message.slice(8, message.length - 8).split(",").map do |value| value.to_i! end
    answer = BlockedAnswer(error: BlockedError(code: "BLOCKED", message: "card is blocked", blocked_by: ids))
    return Bond.json_as(conn, 409, BlockedAnswer.codec, answer).with(halted: true)
  end

  return reject(conn, 409, "CYCLE", "dependency cycle") if message.start_with?("CYCLE:")
  return reject(conn, 409, "NOT_CLAIMER", "agent does not hold the claim") if message.start_with?("NOT_CLAIMER:")
  return reject(conn, 409, "DONE", "card is done") if message.start_with?("DONE:")
  return reject(conn, 409, "CONFLICT", message) if message.start_with?("CONFLICT:")
  return reject(conn, 404, "NO_READY_CARD", "no ready card") if message.start_with?("NO_READY_CARD:")
  return reject(conn, 404, "NOT_FOUND", message) if message.start_with?("NOT_FOUND:")
  return reject(conn, 503, "BUSY", "database busy") if Database.busy?(message)

  reject(conn, 500, "INTERNAL", "internal error")
end

private

struct ApiError
  code: String
  message: String
  field: Optional[String]
end

struct ClaimedError
  code: String
  message: String
  card_id: Int
  claimed_by: String
end

struct ClaimedAnswer
  error: ClaimedError
end

struct BlockedError
  code: String
  message: String
  blocked_by: List[Int]
end

struct BlockedAnswer
  error: BlockedError
end

struct ErrorAnswer
  error: ApiError
end
