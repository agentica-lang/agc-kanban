import Restarts from "../src/kanban_web/restarts"

def test_only_the_same_event_adds_up() -> Result[Void]
  try Test.eq(Restarts.next_failures(0, 0, 7), 1)
  try Test.eq(Restarts.next_failures(7, 1, 7), 2)
  try Test.eq(Restarts.next_failures(7, 4, 7), 5)
  try Test.eq(Restarts.next_failures(7, 4, 8), 1)
  try Test.eq(Restarts.next_failures(7, 4, 0), 1)
  try Test.eq(Restarts.next_failures(0, 3, 0), 1)
  ok()
end
