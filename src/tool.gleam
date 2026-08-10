import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import tool/read_dir
import tool/read_file
import tool_spec

pub fn encode_tools() -> json.Json {
  [read_dir.spec()]
  |> json.array(tool_spec.encode_tool_spec)
}

pub type Tool {
  Invalid
  ReadDir(read_dir.Args)
  ReadFile(read_file.Args)
}

pub fn tool_decoder() {
  let name_decoder = decode.at(["function", "name"], decode.string)

  use name <- decode.then(name_decoder)

  case name {
    "read_dir" -> read_dir.args_decoder() |> decode.map(ReadDir)
    "read_file" -> read_file.args_decoder() |> decode.map(ReadFile)
    _ -> decode.failure(Invalid, "unknown name: " <> name)
  }
}
