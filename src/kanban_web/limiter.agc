## Rate limit of the login and the registration: counts of attempts in a fixed window, in memory (a restart forgets
## them), and a cap on the scrypt hashes that run at once.

## How long a window lasts (5 minutes).
WINDOW_MS = 300_000

## The most scrypt hashes running or waiting at once. The rest is refused at once, so a flood of logins cannot fill
## every connection of the server and stall the CLI and the API.
HASH_LIMIT = 4

## Counts a login try and says whether it may go on: first by address (a flood from one address stops there and
## counts nothing else), then by username and address (the strict limit: 5 tries), then by username alone (a much
## higher limit, so that one address cannot lock a user out for everyone). `username` is normalized.
def login_allowed?(username: String, address: String, now: Int) -> Bool
  return false if not attempt(address_key(address), ADDRESS_LIMIT, now)
  return false if not attempt(pair_key(username, address), PAIR_LIMIT, now)

  attempt(username_key(username), USERNAME_LIMIT, now)
end

## The same for a registration, by address only.
def register_allowed?(address: String, now: Int) -> Bool = attempt(address_key(address), ADDRESS_LIMIT, now)

## Forgets the tries of this username from this address in the window of `now`: its login worked.
def login_succeeded(username: String, address: String, now: Int) -> Void
  ATTEMPTS.delete(slot(pair_key(username, address), now))
end

## Counts one attempt of `key` in the window of `now` and says whether it is within `limit`. The count goes up before
## the caller checks the password, so attempts at the same moment cannot all slip under the limit. A full table
## drops the keys of past windows; when the current window alone fills it, a new key is refused (never forgotten), and
## the keys it holds go on counting.
def attempt(key: String, limit: Int, now: Int) -> Bool
  if ATTEMPTS.size() > MAX_KEYS
    drop_past(now / WINDOW_MS)
  end

  full = ATTEMPTS.size() > MAX_KEYS
  return false if full and not ATTEMPTS.has_key?(slot(key, now))

  ATTEMPTS.add(slot(key, now), 1) <= limit
end

## Takes one of the places for a hash and says whether there was one. Pair it with `end_hash` in the same function.
def start_hash() -> Bool
  return true if HASHING.add(RUNNING, 1) <= HASH_LIMIT

  _ = HASHING.add(RUNNING, -1)
  false
end

## Gives the place of `start_hash` back.
def end_hash() -> Void
  _ = HASHING.add(RUNNING, -1)
end

## Seconds until the window of `now` ends, at least 1: the `Retry-After` of a refused attempt.
def retry_after(now: Int) -> Int = (WINDOW_MS - now % WINDOW_MS) / 1000 + 1

private

ADDRESS_LIMIT = 30
PAIR_LIMIT = 5
USERNAME_LIMIT = 50

# The keys the table may hold. A key is a hash or an address, so it is small.
MAX_KEYS = 10_000

RUNNING = "running"
LAST_DROP = "window"

ATTEMPTS: ATS[String, Int] = ATS.new()
HASHING: ATS[String, Int] = ATS.new()
DROPPED: ATS[String, Int] = ATS.new()

def address_key(address: String) -> String = "address:#{address}"

def pair_key(username: String, address: String) -> String = "pair:#{digest("#{username}\n#{address}")}"

def username_key(username: String) -> String = "user:#{digest(username)}"

def digest(text: String) -> String = OpenSSL.Digest.sha256_hexdigest(text.bytes)

# A slot starts with its window, so the keys of past windows are told by their prefix.
def slot(key: String, now: Int) -> String = "#{now / WINDOW_MS}:#{key}"

# Once per window: a table full of the current window has nothing to drop, and a scan on each try would be a cost.
def drop_past(window: Int) -> Void
  return if DROPPED.get(LAST_DROP).unwrap_or(-1) == window

  DROPPED.put(LAST_DROP, window)
  prefix = "#{window}:"
  for key in ATTEMPTS.keys()
    if not key.start_with?(prefix)
      ATTEMPTS.delete(key)
    end
  end
end
