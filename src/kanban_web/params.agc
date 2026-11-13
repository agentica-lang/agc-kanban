def number(params: Map[String, List[String]], name: String, default: Int) -> Result[Int]
  case params.get(name)
    none -> ok(default)
    some(values) -> values[0].to_i()
  end
end

def text(params: Map[String, List[String]], name: String) -> Optional[String]
  case params.get(name)
    none -> none
    some(values) -> some(values[0])
  end
end

def flag(params: Map[String, List[String]], name: String) -> Result[Optional[Bool]]
  case text(params, name)
    none -> ok(none)
    some("1") -> ok(some(true))
    some("0") -> ok(some(false))
    _ -> error("invalid boolean")
  end
end
