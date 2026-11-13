import Claimer from "../src/kanban_web/claimer"

# The shared file: the answer for every hue and the hue of some names. test/web/claimer.test.mjs checks the board's
# script (app/javascript/claimer.js) against the same file, so the board and the home page draw the same chip.
struct Shared
  light: List[Bool]
  hues: Map[String, Int]
end

def shared() -> Result[Shared] = JSON.decode(try File.read_text("test/claimer_light.json"), Shared)

def test_every_hue_has_the_tone_of_the_shared_file() -> Result[Void]
  light = (try shared()).light
  try Test.eq(light.size, 360)
  for degrees in 0...360
    try Test.eq(Claimer.light?(degrees), light[degrees])
  end

  ok()
end

def test_the_hue_of_a_name_is_the_one_of_the_shared_file() -> Result[Void]
  hues = (try shared()).hues
  try Test.eq(hues.size, 6)
  for name in hues.keys
    try Test.eq(Claimer.hue(name), hues[name])
  end

  ok()
end
