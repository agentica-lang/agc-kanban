## The password rules of the web login, and the slow salted hash that the store keeps instead of the password.

import Regex from "std/regex"

MIN_LENGTH = 8
MAX_LENGTH = 16

## What a password lacks, as phrases for an error message ("must be 8 to 16 characters long (it has 5)"); empty when
## it passes.
def problems(password: String) -> List[String]
  found: List[String] = []
  if password.length < MIN_LENGTH or password.length > MAX_LENGTH
    found = found.push("must be #{MIN_LENGTH} to #{MAX_LENGTH} characters long (it has #{password.length})")
  end

  if not Regex.match?(password, /[A-Z]/)
    found = found.push("needs an uppercase letter (A-Z)")
  end

  if not Regex.match?(password, /[a-z]/)
    found = found.push("needs a lowercase letter (a-z)")
  end

  if not Regex.match?(password, /[0-9]/)
    found = found.push("needs a number (0-9)")
  end

  if not Regex.match?(password, /[^A-Za-z0-9]/)
    found = found.push("needs a special character (any that is not a letter or a number, such as ! @ # $ % & * - _ ?)")
  end

  found
end

## The text kept for a password: `scrypt$N$r$p$salt$key`, the parameters and a new random salt beside the derived key.
def hash(password: String) -> Result[String]
  salt = OpenSSL.Random.random_bytes(SALT_BYTES)
  key = try OpenSSL.KDF.scrypt(password.bytes, salt, COST, BLOCK_SIZE, PARALLEL, KEY_BYTES)
  ok("scrypt$#{COST}$#{BLOCK_SIZE}$#{PARALLEL}$#{OpenSSL.Digest.hexencode(salt)}$#{OpenSSL.Digest.hexencode(key)}")
end

## The password is the one that `stored` (from `hash`) was made from. The key is compared in constant time; a stored
## text that cannot be read is no match.
def verify(password: String, stored: String) -> Bool = matches(password, stored).unwrap_or(false)

## The work of `verify` against a text that never matches: a login of an unknown user takes as long as a wrong password.
def verify_nobody(password: String) -> Bool = verify(password, NOBODY)

private

# The OWASP advice for scrypt: N = 2^17 (128 MiB), r = 8, p = 1.
COST = 131072
BLOCK_SIZE = 8
PARALLEL = 1
SALT_BYTES = 16
KEY_BYTES = 32

# A well-formed text with the cost of the real ones and no password behind it.
NOBODY = (
  "scrypt$131072$8$1$00000000000000000000000000000000$0000000000000000000000000000000000000000000000000000000000000000"
)

def matches(password: String, stored: String) -> Result[Bool]
  parts = stored.split("$")
  return error("unknown hash format") if parts.size != 6 or parts[0] != "scrypt"

  cost = try parts[1].to_i()
  block_size = try parts[2].to_i()
  parallel = try parts[3].to_i()
  salt = try OpenSSL.Digest.hexdecode(parts[4])
  expected = try OpenSSL.Digest.hexdecode(parts[5])
  key = try OpenSSL.KDF.scrypt(password.bytes, salt, cost, block_size, parallel, expected.size)
  ok(OpenSSL.HMAC.secure_compare(key, expected))
end
