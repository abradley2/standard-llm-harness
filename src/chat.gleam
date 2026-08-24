import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import tool.{type Tool}

pub type ChatRole {
  ChatRoleUser
  ChatRoleTool
  ChatRoleAssistant
}

fn chat_role_to_string(chat_role: ChatRole) -> String {
  case chat_role {
    ChatRoleUser -> "user"
    ChatRoleTool -> "tool"
    ChatRoleAssistant -> "assistant"
  }
}

pub type ChatResponse {
  ChatResponse(content: String, tool_calls: List(Tool))
}

pub fn chat_response_decoder() -> decode.Decoder(ChatResponse) {
  use tool_calls <- decode.then(decode.at(
    ["message", "tool_calls"],
    decode.list(tool.tool_decoder()),
  ))

  use content <- decode.then(decode.at(["message", "content"], decode.string))

  ChatResponse(content, tool_calls) |> decode.success
}

pub type ChatMessage {
  ChatMessage(role: ChatRole, content: String, tool_name: Option(String))
}

fn chat_message_to_json(chat_message: ChatMessage) -> json.Json {
  let tool_attrs = case chat_message.tool_name {
    Some(tool_name) -> [#("tool_name", tool_name |> json.string)]
    None -> []
  }

  json.object(
    [
      #("role", chat_message.role |> chat_role_to_string |> json.string),
      #("content", chat_message.content |> json.string),
    ]
    |> list.append(tool_attrs),
  )
}
