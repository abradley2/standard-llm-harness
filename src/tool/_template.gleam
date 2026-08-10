import gleam/dynamic/decode
import gleam/json
import tool_spec

pub type Args {
  Args(id: String)
}

pub fn args_decoder() -> decode.Decoder(Args) {
  todo
}

pub fn run(args: Args) -> json.Json {
  todo
}

pub fn spec() -> tool_spec.ToolSpec {
  tool_spec.ToolSpec(
    name: "todo",
    description: "todo: add description",
    parameters: [
      #("id", tool_spec.SpecTypeString),
    ],
  )
}
