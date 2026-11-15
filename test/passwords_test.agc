import Passwords from "../src/kanban/passwords"

def test_a_password_with_every_class_passes() -> Result[Void]
  try Test.eq(Passwords.problems("Abcdef1!"), [])
  Test.eq(Passwords.problems("Abcdefgh1!Abcdef"), [])
end

def test_each_missing_rule_is_named() -> Result[Void]
  try Test.eq(Passwords.problems("Abcdef1!x").size, 0)
  try Test.eq(Passwords.problems("Abcdef1").size, 2)
  try Test.eq(Passwords.problems("Abcdef1!Abcdef1!x"), ["must be 8 to 16 characters long (it has 17)"])
  try Test.eq(Passwords.problems("abcdefg1!").size, 1)
  try Test.eq(Passwords.problems("ABCDEFG1!").size, 1)
  try Test.eq(Passwords.problems("Abcdefgh!").size, 1)
  Test.eq(Passwords.problems("Abcdefg12").size, 1)
end

# What `hash` writes is what `verify` reads, with a salt of its own each time.
def test_a_hash_verifies_only_its_password() -> Result[Void]
  first = try Passwords.hash("Abcdef1!")
  second = try Passwords.hash("Abcdef1!")
  try Test.eq(first.start_with?("scrypt$131072$8$1$"), true)
  try Test.eq(first == second, false)
  try Test.eq(Passwords.verify("Abcdef1!", first), true)
  try Test.eq(Passwords.verify("Abcdef1?", first), false)
  try Test.eq(Passwords.verify("Abcdef1!", "plain text"), false)
  Test.eq(Passwords.verify_nobody("Abcdef1!"), false)
end
