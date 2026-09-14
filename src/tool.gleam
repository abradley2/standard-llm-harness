import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json.{type Json}
import tool/read_dir
import tool/read_file
import tool_spec

pub fn encode_tools() -> json.Json {
  [read_dir.spec(), read_file.spec()]
  |> json.array(tool_spec.encode_tool_spec)
}

pub type ToolCall {
  Invalid
  ReadDir(read_dir.Args)
  ReadFile(read_file.Args)
}

pub type ToolResponse {
  ToolResponse(tool_name: String, json_content: String)
}

pub fn as_tool_response(tool_name: String) {
  fn(tool_call_result: Json) -> ToolResponse {
    ToolResponse(tool_name, tool_call_result |> json.to_string)
  }
}

pub fn resolve_tool_call(tool_call: ToolCall) -> ToolResponse {
  case tool_call {
    Invalid ->
      json.null()
      |> as_tool_response("invalid")
    ReadDir(args) ->
      read_dir.run(args)
      |> as_tool_response("read_dir")
    ReadFile(args) ->
      read_file.run(args)
      |> as_tool_response("read_file")
  }
}

pub fn tool_decoder() -> decode.Decoder(ToolCall) {
  let name_decoder = decode.at(["function", "name"], decode.string)

  use name <- decode.then(name_decoder)

  case name {
    "read_dir" ->
      read_dir.args_decoder()
      |> for_arguments()
      |> decode.map(ReadDir)
    "read_file" ->
      read_file.args_decoder()
      |> for_arguments()
      |> decode.map(ReadFile)

    _ -> decode.failure(Invalid, "unknown name: " <> name)
  }
}

fn for_arguments(decoder: decode.Decoder(a)) -> decode.Decoder(a) {
  decode.at(["arguments"], decoder)
}
