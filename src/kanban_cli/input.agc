import {Kind, Opt} from "std/option_parser"

# Long text and id lists shared by the card commands.

export struct Repeated
  values: List[String]
  rest: List[String]
end

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

# The values of an option that may repeat (`--link A --link=B`), taken out of the words before the option parser, which
# keeps only the last one. The scan stops at `--`, and the word after another option that takes a value is that value
# (`--body --link` is a body), so `opts` are the options of the command.
export def repeated(words: List[String], name: String, opts: List[Opt]) -> Result[Repeated]
  flag = "--#{name}"
  valued = opts.select do |opt| opt.kind != Kind.Flag end.map do |opt| "--#{opt.name}" end
  values: List[String] = []
  rest: List[String] = []
  i = 0
  while i < words.size
    word = words[i]
    if word == "--"
      return ok(Repeated(values: values, rest: rest + List.drop(words, i)))
    elsif word == flag
      return error("#{flag} needs a value") if i + 1 >= words.size

      values = values.push(words[i + 1])
      i += 2
    elsif word.start_with?("#{flag}=")
      values = values.push(word.slice(flag.length + 1, word.length - flag.length - 1))
      i += 1
    elsif valued.include?(word) and i + 1 < words.size
      rest = rest.push(word).push(words[i + 1])
      i += 2
    else
      rest = rest.push(word)
      i += 1
    end
  end

  ok(Repeated(values: values, rest: rest))
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
