## Rate limit of the login and the registration: a count of attempts per key in a fixed window, in memory (a restart
## forgets it). A key is a username or an address, so a password cannot be guessed at full speed for one user, nor
## from one address.

## How long a window lasts (5 minutes).
WINDOW_MS = 300_000

## Counts one attempt of `key` in the window of `now` and says whether it is within `limit`. The count goes up before
## the caller checks the password, so attempts at the same moment cannot all slip under the limit.
def attempt(key: String, limit: Int, now: Int) -> Bool
  if ATTEMPTS.size() > MAX_KEYS
    for stale in ATTEMPTS.keys()
      ATTEMPTS.delete(stale)
    end
  end

  ATTEMPTS.add(slot(key, now), 1) <= limit
end

## Forgets the attempts of `key` in the window of `now`: its login worked.
def forgive(key: String, now: Int) -> Void
  ATTEMPTS.delete(slot(key, now))
end

## Seconds until the window of `now` ends, at least 1: the `Retry-After` of a refused attempt.
def retry_after(now: Int) -> Int = (WINDOW_MS - now % WINDOW_MS) / 1000 + 1

private

# Past this many keys the table is emptied: a flood of made-up names cannot grow it without end.
MAX_KEYS = 10_000

ATTEMPTS: ATS[String, Int] = ATS.new()

def slot(key: String, now: Int) -> String = "#{now / WINDOW_MS}:#{key}"
