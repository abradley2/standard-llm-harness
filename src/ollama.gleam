import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
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

pub fn assistant_message_decoder() -> decode.Decoder(OllamaChatResponse) {
  use tool_calls <- decode.then(decode.at(
    ["message", "tool_calls"],
    decode.list(tool.tool_decoder()),
  ))

  use content <- decode.then(decode.at(["message", "content"], decode.string))
  use role <- decode.then(decode.at(["message", "role"], decode.string))

  case role == "assistant" {
    True -> OllamaChatResponse(content, tool_calls) |> decode.success
    False ->
      decode.failure(
        OllamaChatResponse("", []),
        "Chat message does not have assistant role! Found: " <> role,
      )
  }
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

pub fn invoke_ollama_chat(
  chat_messages: List(ChatMessage),
) -> Result(OllamaChatResponse, String) {
  use ollama_uri <- result.try(
    uri.parse("http://localhost:11434/api/chat")
    |> result.replace_error("failed to create ollama chat uri"),
  )

  use ollama_req <- result.try(
    request.from_uri(ollama_uri)
    |> result.replace_error("Failed to create ollama chat request")
    |> result.map(request.set_body(
      _,
      json.object([
        #("messages", json.array(chat_messages, chat_message_to_json)),
      ])
        |> json.to_string,
    )),
  )

  use ollama_res <- result.try(
    ollama_req
    |> httpc.send
    |> result.replace_error("Failed to get ollama chat response"),
  )

  use decoded_ollama_res <- result.try(
    json.parse(from: ollama_res.body, using: assistant_message_decoder())
    |> result.replace_error("Unabled to decode: " <> ollama_res.body),
  )

  Ok(decoded_ollama_res)
}

pub type OllamaChatResponse {
  OllamaChatResponse(content: String, tool_calls: List(ToolCall))
}
