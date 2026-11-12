## The count of consecutive failures of the live send of one event.

## The count after one more failure of the send of event `id`: `bad` and `count` are the event and the count of the
## failure before. A failure on a different event starts again at 1, so only the same event, over and over, is a
## poison event. Event ids start at 1.
export def next_failures(bad: Int, count: Int, id: Int) -> Int
  return count + 1 if id == bad

  1
end
