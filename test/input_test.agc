import Input from "../src/kanban_cli/input"

def test_text_and_lists() -> Result[Void]
  try Test.eq(try Input.text(some("hi"), none), some("hi"))
  try Test.eq(try Input.text(none, none), none)
  try Test.eq(Input.text(some("hi"), some("f")).ok?, false)
  try Test.eq(Input.csv(some("api, ui")), ["api", "ui"])
  try Test.eq(Input.csv(none), [])
  try Test.eq(Input.csv(some("")), [])
  try Test.eq(try Input.ids(some("1, 2")), [1, 2])
  try Test.eq(Input.ids(some("x")).ok?, false)

  home = try System.env("HOME")
  cache = "#{home}/.cache"
  try Dir.mkdir(cache)
  path = "#{cache}/kanban-input-test-#{System.pid()}.txt"
  try File.write_text(path, "from a file")
  try Test.eq(try Input.text(none, some(path)), some("from a file"))
  try Test.eq(Input.text(none, some("#{cache}/kanban-input-test-missing.txt")).ok?, false)
  Path.remove(path)
end
