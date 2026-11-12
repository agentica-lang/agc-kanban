import Claimer from "../src/kanban_web/claimer"

# The answer for every hue, from test/claimer_light.json. test/web/claimer.test.mjs checks the board's script
# (app/javascript/claimer.js) against the same file, so the board and the home page draw the same chip.
def test_every_hue_has_the_tone_of_the_shared_file() -> Result[Void]
  light = try JSON.decode(try File.read_text("test/claimer_light.json"), List[Bool])
  try Test.eq(light.size, 360)
  for degrees in 0...360
    try Test.eq(Claimer.light?(degrees), light[degrees])
  end

  ok()
end

def test_the_hue_of_a_name_is_the_one_the_board_draws() -> Result[Void]
  try Test.eq(Claimer.hue("bob"), 157)
  try Test.eq(Claimer.hue("seed"), 57)
  try Test.eq(Claimer.hue("claude-code"), 28)
  ok()
end
