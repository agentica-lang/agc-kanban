# Long text and id lists shared by the card commands.

export def text(body: Optional[String], file: Optional[String]) -> Result[Optional[String]]
  return error("use --body or --body-file, not both") if body.some? and file.some?

  return ok(some(try read(file.unwrap!))) if file.some?

  case body
    some(value) -> ok(some(read_value(value)))
    none -> ok(none)
  end
end

export def csv(value: Optional[String]) -> List[String]
  return [] if value.none?

  value.unwrap!.split(",").select do |part| not part.strip.empty? end.map do |part| part.strip end
end

export def ids(value: Optional[String]) -> Result[List[Int]]
  found: List[Int] = []
  for part in csv(value)
    found = found.push(try part.to_i)
  end

  ok(found)
end

# `-` reads standard input, so a caller can pipe a long body.
def read(path: String) -> Result[String]
  return ok(IO.read()) if path == "-"

  File.read_text(path)
end

def read_value(value: String) -> String
  return IO.read() if value == "-"

  value
end
