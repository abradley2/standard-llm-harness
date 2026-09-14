import gleam/dynamic/decode
import gleam/json
import tool_spec

pub type Args {
  Args(number: Float)
}

pub fn args_decoder() -> decode.Decoder(Args) {
  use number <- decode.field("number", decode.float)

  decode.success(Args(number: number))
}

pub fn run(args: Args) -> json.Json {
  let doubled = args.number * 2

  json.float(doubled)
}

pub fn spec() -> tool_spec.ToolSpec {
  tool_spec.ToolSpec(
    name: "double",
    description: "double a number",
    parameters: [
      #("number", tool_spec.SpecTypeString),
    ],
  )
}
