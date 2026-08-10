import gleam/json
import gleam/list

pub type SpecType {
  SpecTypeInteger
  SpecTypeNumber
  SpecTypeString
  SpecTypeList(SpecType)
  SpecTypeRecord(List(#(String, SpecType)))
}

pub fn encode_schema_type(schema_type) -> json.Json {
  case schema_type {
    SpecTypeInteger -> json.object([#("type", json.string("integer"))])
    SpecTypeNumber -> json.object([#("type", json.string("number"))])
    SpecTypeString -> json.object([#("type", json.string("string"))])
    SpecTypeList(sub_type) ->
      json.object([
        #("type", json.string("array")),
        #("items", encode_schema_type(sub_type)),
      ])
    SpecTypeRecord(properties) ->
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          properties
            |> list.map(fn(property_pair) {
              let #(property_name, property_type) = property_pair
              #(property_name, property_type |> encode_schema_type)
            })
            |> json.object,
        ),
        #(
          "required",
          properties |> list.map(fn(pair) { pair.0 }) |> json.array(json.string),
        ),
      ])
  }
}

pub type ToolSpec {
  ToolSpec(
    name: String,
    description: String,
    parameters: List(#(String, SpecType)),
  )
}

pub fn encode_tool_spec(tool_spec: ToolSpec) -> json.Json {
  json.object([
    #("type", json.string("function")),
    #(
      "function",
      json.object([
        #("name", tool_spec.name |> json.string),
        #("description", tool_spec.description |> json.string),
        #(
          "parameters",
          SpecTypeRecord(tool_spec.parameters)
            |> encode_schema_type,
        ),
        #(
          "required",
          tool_spec.parameters
            |> list.map(fn(pair) { pair.0 })
            |> json.array(json.string),
        ),
      ]),
    ),
  ])
}
