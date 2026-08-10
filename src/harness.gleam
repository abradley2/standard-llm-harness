import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/uri

import mist.{type Connection, type ReadError, type ResponseData, Bytes}

pub fn read_error_to_string(err: ReadError) -> String {
  case err {
    mist.MalformedBody -> "MalformedBody"
    mist.ExcessBody -> "ExcessBody"
  }
}

pub type ChatCommand {
  ChatCommandNext(String, reply_with: Subject(Action))
  ChatCommandStop
}

pub type Action {
  ActionContinue(requests: List(String))
  ActionDone(output: String)
  ActionError(reason: String)
}

pub type GenerateRequestState {
  GenerateRequestStatePending
  GenerateRequestStateDone(String)
  GenerateRequestStateError(String)
}

pub type State {
  State(chat: List(ChatMessage), generate_requests: List(GenerateRequestState))
}

pub type GenerateRequest {
  GenerateRequest(name: String)
}

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

pub type ChatMessage {
  ChatMessage(role: ChatRole, content: String)
}

fn chat_message_to_json(chat_message: ChatMessage) -> json.Json {
  json.object([
    #("role", chat_message.role |> chat_role_to_string |> json.string),
    #("content", chat_message.content |> json.string),
  ])
}

fn action(
  state: State,
  reply_subject: Subject(Action),
  action: Action,
) -> actor.Next(State, never) {
  process.send(reply_subject, action)
  actor.continue(state)
}

fn handle_chat_command(
  state: State,
  cmd: ChatCommand,
) -> actor.Next(State, never) {
  case cmd {
    ChatCommandNext(msg, reply_subject) -> {
      let state =
        State(
          ..state,
          chat: list.append(state.chat, [
            ChatMessage(role: ChatRoleUser, content: msg),
          ]),
        )

      let ollama_response = invoke_ollama_chat(state.chat)

      case ollama_response {
        Error(err_response) -> {
          action(state, reply_subject, ActionError(err_response))
        }
        Ok(next_chat_msg) -> {
          State(
            ..state,
            chat: list.append(state.chat, [
              ChatMessage(role: ChatRoleAssistant, content: next_chat_msg),
            ]),
          )
          |> action(reply_subject, ActionContinue([]))
        }
      }
    }
    ChatCommandStop -> actor.stop()
  }
}

fn make_chat_actor() -> Result(
  actor.Started(process.Subject(ChatCommand)),
  actor.StartError,
) {
  actor.new(State([], []))
  |> actor.on_message(handle_chat_command)
  |> actor.start
}

pub fn text_error_response(
  status: Int,
  content: String,
) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("Content-Type", "text/plain")
  |> response.set_body(Bytes(bytes_tree.from_string(content)))
}

pub fn invoke_ollama_chat(
  chat_messages: List(ChatMessage),
) -> Result(String, String) {
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
        #("chat", json.array(chat_messages, chat_message_to_json)),
      ])
        |> json.to_string,
    )),
  )

  use ollama_res <- result.try(
    ollama_req
    |> httpc.send
    |> result.replace_error("Failed to get ollama chat response"),
  )

  Ok(ollama_res.body)
}

pub fn handler(
  req: Request(Connection),
) -> Result(Response(ResponseData), Response(ResponseData)) {
  use client_body <- result.try(
    mist.read_body(req, 1024 * 1024 * 4)
    |> result.map(fn(req) { req.body })
    |> result.map_error(read_error_to_string)
    |> result.map_error(fn(err) {
      text_error_response(400, "Failed to read request body: " <> err)
    }),
  )

  use ollama_uri <- result.try(
    uri.parse("http://localhost:11434/api/chat")
    |> result.replace_error(text_error_response(
      500,
      "failed to create ollama chat uri",
    )),
  )

  use ollama_req <- result.try(
    request.from_uri(ollama_uri)
    |> result.replace_error(text_error_response(
      500,
      "Failed to create ollama chat request",
    ))
    |> result.map(request.set_body(_, client_body)),
  )

  use ollama_res <- result.try(
    ollama_req
    |> httpc.send_bits
    |> result.replace_error(text_error_response(
      500,
      "Failed to get ollama chat response",
    )),
  )

  use ollama_res_body <- result.try(
    ollama_res.body
    |> bit_array.to_string
    |> result.replace_error(text_error_response(
      500,
      "Failed to decode utf-8 from ollama chat response body",
    )),
  )

  todo
}

pub fn main() -> Nil {
  let a =
    mist.new(fn(req: Request(Connection)) -> Response(ResponseData) {
      case handler(req) {
        Ok(res) -> res
        Error(res) -> res
      }
    })
  io.println("Hello from woodhouse!")
}
