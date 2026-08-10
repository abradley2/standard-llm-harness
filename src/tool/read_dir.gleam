import gleam/dynamic/decode
import gleam/json
import tool_spec

pub type Args {
  Args(path: String)
}

pub fn args_decoder() -> decode.Decoder(Args) {
  use path <- decode.field("path", decode.string)

  decode.success(Args(path))
}

pub fn run(args: Args) -> json.Json {
  json.string("placeholder")
}

pub fn spec() -> tool_spec.ToolSpec {
  tool_spec.ToolSpec(
    name: "read_file",
    description: "Read a file at a given path, relative to the current working directory. Returns the contents of the target file",
    parameters: [#("path", tool_spec.SpecTypeString)],
  )
}
