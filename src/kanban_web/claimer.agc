## The chip of the agent that holds a card on the home page, as app/javascript/claimer.js draws it on the board: a hue
## from the name, and whether the chip is light (dark text) or dark (white text). The two files keep the same
## arithmetic; test/claimer_light.json holds the answer for every hue and both are tested against it.

# The color the chip had before it had tones: hsl(hue 60% 45%). A hue whose color is brighter than LIGHT_ABOVE gets the
# light chip. The brightness squares each channel (sRGB with a gamma of 2, not 2.4) because there is no `pow` here; the
# choice only needs to be right to a few percent, since both tones keep 5:1 around the switch, and
# test/web/styles.test.mjs measures the real contrast of every hue.
SATURATION = 0.6
LIGHTNESS = 0.45
LIGHT_ABOVE = 0.2

## A color from the name, so an agent keeps one color on both pages.
export def hue(name: String) -> Int
  sum = 0
  for char in name.split("")
    sum = (sum * 31 + char.code) % 360
  end

  sum
end

## Whether the chip of this hue is light, with dark text.
export def light?(degrees: Int) -> Bool
  red = channel(0, degrees)
  green = channel(8, degrees)
  blue = channel(4, degrees)
  0.2126 * red * red + 0.7152 * green * green + 0.0722 * blue * blue > LIGHT_ABOVE
end

# One channel of hsl(hue, SATURATION, LIGHTNESS) as the CSS Color spec writes it: `n` is 0, 8 or 4 for red,
# green, blue.
def channel(n: Int, degrees: Int) -> Float
  raw = n.to_f + degrees.to_f / 30.0
  k = raw - 12.0 * (raw / 12.0).floor.to_f
  top = [k - 3.0, 9.0 - k].min.unwrap!
  LIGHTNESS - SATURATION * LIGHTNESS * top.clamp(-1.0, 1.0)
end
