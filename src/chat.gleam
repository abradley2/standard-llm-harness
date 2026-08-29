import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import tool.{type ToolCall}

pub type ChatMessage {
  AssistantMessage(content: String, tool_calls: List(ToolCall))
  ToolMessage(content: String, tool_name: String)
  UserMessage(content: String)
}

fn chat_message_tool_name(chat_message: ChatMessage) -> Option(String) {
  case chat_message {
    ToolMessage(_, tool_name) -> Some(tool_name)
    _ -> None
  }
}

fn chat_message_content(chat_message: ChatMessage) -> String {
  case chat_message {
    AssistantMessage(content, _) -> content
    ToolMessage(content, _) -> content
    UserMessage(content) -> content
  }
}

fn chat_message_role(chat_message: ChatMessage) -> String {
  case chat_message {
    AssistantMessage(_, _) -> "user"
    ToolMessage(_, _) -> "tool"
    UserMessage(_) -> "assistant"
  }
}

pub fn assistant_message_decoder() -> decode.Decoder(ChatMessage) {
  use tool_calls <- decode.then(decode.at(
    ["message", "tool_calls"],
    decode.list(tool.tool_decoder()),
  ))

  use content <- decode.then(decode.at(["message", "content"], decode.string))

  AssistantMessage(content, tool_calls) |> decode.success
}

pub fn chat_message_to_json(chat_message: ChatMessage) -> json.Json {
  let tool_attrs = case chat_message_tool_name(chat_message) {
    Some(tool_name) -> [#("tool_name", tool_name |> json.string)]
    None -> []
  }

  json.object(
    [
      #("role", chat_message |> chat_message_role |> json.string),
      #("content", chat_message.content |> json.string),
    ]
    |> list.append(tool_attrs),
  )
}
