import Limiter from "../src/kanban_web/limiter"

# The tests share the table of the limiter, so each one lives in windows of its own.
WINDOW = 300_000

# A user is locked from the address that missed five times, not from another one, and an address that is over its
# limit counts nothing for the user.
def test_the_strict_limit_is_per_username_and_address() -> Result[Void]
  now = 10 * WINDOW
  for _ in 1..5
    try Test.eq(Limiter.login_allowed?("owner", "10.0.0.1", now), true)
  end

  try Test.eq(Limiter.login_allowed?("owner", "10.0.0.1", now), false)
  try Test.eq(Limiter.login_allowed?("owner", "10.0.0.2", now), true)
  try Test.eq(Limiter.login_allowed?("owner", "10.0.0.1", now + WINDOW), true)
  Limiter.login_succeeded("owner", "10.0.0.2", now)
  try Test.eq(Limiter.login_allowed?("owner", "10.0.0.2", now), true)

  # Thirty tries from one address with made-up names stop it, and the next names are not counted.
  for n in 1..30
    try Test.eq(Limiter.login_allowed?("name-#{n}", "10.0.0.3", now), true)
  end

  try Test.eq(Limiter.login_allowed?("target", "10.0.0.3", now), false)
  Test.eq(Limiter.login_allowed?("target", "10.0.0.4", now), true)
end

# A username alone has a higher limit, shared by every address.
def test_one_username_from_many_addresses_hits_the_high_limit() -> Result[Void]
  now = 20 * WINDOW
  for n in 1..50
    try Test.eq(Limiter.login_allowed?("victim", "10.1.0.#{n}", now), true)
  end

  Test.eq(Limiter.login_allowed?("victim", "10.1.1.1", now), false)
end

# A full table drops the keys of past windows, and when the current window fills it alone, a new key is refused while
# the keys it holds go on counting: nothing is forgotten.
def test_a_full_table_never_forgets_the_current_window() -> Result[Void]
  old = 30 * WINDOW
  for n in 0..10_000
    try Test.eq(Limiter.attempt("old-#{n}", 5, old), true)
  end

  now = 31 * WINDOW
  try Test.eq(Limiter.attempt("held", 1, now), true)
  for n in 0..10_000
    _ = Limiter.attempt("new-#{n}", 5, now)
  end

  try Test.eq(Limiter.attempt("one-more", 5, now), false)
  # The first key still counts (its second try is over a limit of 1), and a new window starts clean.
  try Test.eq(Limiter.attempt("held", 1, now), false)
  Test.eq(Limiter.attempt("one-more", 5, 32 * WINDOW), true)
end

def test_only_four_hashes_run_at_once() -> Result[Void]
  for _ in 1..Limiter.HASH_LIMIT
    try Test.eq(Limiter.start_hash(), true)
  end

  try Test.eq(Limiter.start_hash(), false)
  Limiter.end_hash()
  try Test.eq(Limiter.start_hash(), true)
  for _ in 1..Limiter.HASH_LIMIT
    Limiter.end_hash()
  end

  Test.eq(Limiter.start_hash(), true)
end
