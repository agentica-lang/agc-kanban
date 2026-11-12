## The count of consecutive crashes of the live publisher on one event.

## The count after one more crash. `handling` is the id of the event the publisher was sending when it crashed, or 0
## when it crashed outside an event; `bad` and `count` are the id and the count of the crash before. A crash on a
## different event, or outside one, starts again at 1: only the same event, over and over, is a poison event.
export def next_failures(bad: Int, count: Int, handling: Int) -> Int
  return count + 1 if handling > 0 and handling == bad

  1
end
