## The count of consecutive failures of the live send of one event.

## The count after one more crash. `handling` is the id of the event whose send failed, or 0 for none; `bad` and `count` are the
## id and the count of the failure before. A failure on a different event starts again at 1: only the same event,
## over and over, is a poison event.
export def next_failures(bad: Int, count: Int, handling: Int) -> Int
  return count + 1 if handling > 0 and handling == bad

  1
end
