import gleam/dynamic/decode
import gleam/json
import tool_spec

pub const description = "
Reads a file at the given path.
The path is relative to the current working directory.
"

pub type Args {
  Args(path: String)
}

pub fn args_decoder() -> decode.Decoder(Args) {
  use path <- decode.field("path", decode.string)

  decode.success(Args(path))
}

pub fn run(args: Args) -> json.Json {
  todo
}

pub fn spec() -> tool_spec.ToolSpec {
  tool_spec.ToolSpec(name: "read_file", description: description, parameters: [
    #("path", tool_spec.SpecTypeString),
  ])
}
