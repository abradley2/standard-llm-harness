import gleam/erlang/process.{type Pid, type Subject}
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Next}
import ollama.{
  type ChatMessage, type OllamaChatResponse, AssistantMessage,
  OllamaChatResponse, ToolMessage, UserMessage,
}
import tool.{type ToolCall, type ToolResponse}

pub type ChatActorState {
  ChatActorState(
    error: Option(String),
    messages: List(ChatMessage),
    tool_queries: List(Pid),
  )
}

pub type ChatActorMessage {
  ChatActorMessageContinue(reply_with: Subject(ChatActorReply))
  ChatActorMessageToolsInvoked(pids: List(Pid))
  ChatActorMessageToolResponse(
    pid: Pid,
    tool_result: Result(ToolResponse, String),
  )
  ChatActorMessageStop
}

pub type ChatActorReply {
  ChatActorReplyToolQueries(query_payloads: List(ToolCall))
  ChatActorReplyWait
  ChatActorReplyDone(output: Result(String, String))
}

pub fn tool_response_to_chat_message(tool_response: ToolResponse) -> ChatMessage {
  ToolMessage(
    tool_name: tool_response.tool_name,
    content: tool_response.json_content,
  )
}

pub fn chat_actor_handle_message(
  state: ChatActorState,
  message: ChatActorMessage,
) -> Next(ChatActorState, ChatActorMessage) {
  case state.error, message {
    _, ChatActorMessageToolsInvoked(tool_pids) -> {
      actor.continue(ChatActorState(..state, tool_queries: tool_pids))
    }
    _, ChatActorMessageToolResponse(_, Error(_incoming_tool_response_error)) -> {
      actor.continue(ChatActorState(..state, error: Some("This is an error!")))
    }
    _,
      ChatActorMessageToolResponse(
        incoming_tool_pid,
        Ok(incoming_tool_response),
      )
    -> {
      state.tool_queries
      |> list.fold(
        ChatActorState(..state, tool_queries: []),
        fn(prev_state, waiting_pid) {
          case incoming_tool_pid == waiting_pid {
            True ->
              ChatActorState(
                ..prev_state,
                messages: prev_state.messages
                  |> list.append([
                    tool_response_to_chat_message(incoming_tool_response),
                  ]),
              )
            False ->
              ChatActorState(
                ..prev_state,
                tool_queries: prev_state.tool_queries
                  |> list.append([waiting_pid]),
              )
          }
        },
      )
      |> actor.continue
    }
    Some(_err), ChatActorMessageContinue(reply_subject) -> {
      process.send(
        reply_subject,
        ChatActorReplyDone(Error("Some error happend")),
      )
      actor.continue(state)
    }
    None, ChatActorMessageContinue(reply_subject) -> {
      case state.tool_queries {
        [] -> {
          case ollama.invoke_ollama_chat(state.messages) {
            Ok(OllamaChatResponse(assistant_message, [])) -> {
              process.send(
                reply_subject,
                ChatActorReplyDone(Ok(assistant_message)),
              )
              actor.continue(state)
            }
            Ok(OllamaChatResponse(assistant_message, tool_calls)) -> {
              process.send(reply_subject, ChatActorReplyToolQueries(tool_calls))
              actor.continue(
                ChatActorState(
                  ..state,
                  messages: state.messages
                    |> list.append([
                      AssistantMessage(assistant_message, tool_calls),
                    ]),
                ),
              )
            }
            Error(reason) -> {
              process.send(reply_subject, ChatActorReplyDone(Error(reason)))
              actor.continue(ChatActorState(..state, error: Some(reason)))
            }
          }
        }
        _ -> {
          process.send(reply_subject, ChatActorReplyWait)
          actor.continue(state)
        }
      }
    }

    _, ChatActorMessageStop -> actor.stop()
  }
}

pub fn make_chat_actor(
  initial_chat_message: String,
) -> #(Pid, Subject(ChatActorMessage)) {
  let assert Ok(chat_actor) =
    actor.new(
      ChatActorState(
        error: None,
        messages: [UserMessage(initial_chat_message)],
        tool_queries: [],
      ),
    )
    |> actor.on_message(chat_actor_handle_message)
    |> actor.start

  let subject = chat_actor.data

  #(chat_actor.pid, subject)
}

pub fn tool_query_to_process(
  chat_actor_subject: Subject(ChatActorMessage),
  tool_query_payload: ToolCall,
) -> Pid {
  process.spawn(fn() {
    process.send(
      chat_actor_subject,
      ChatActorMessageToolResponse(
        process.self(),
        Ok(tool.resolve_tool_call(tool_query_payload)),
      ),
    )
  })
}

pub fn run_actor(
  chat_actor_subject: Subject(ChatActorMessage),
) -> Result(String, String) {
  let tool_calls_or_done =
    process.call(chat_actor_subject, 1000 * 60, ChatActorMessageContinue)

  case tool_calls_or_done {
    ChatActorReplyToolQueries(queries) -> {
      let pids =
        queries
        |> list.map(tool_query_to_process(chat_actor_subject, _))

      process.send(chat_actor_subject, ChatActorMessageToolsInvoked(pids))
      run_actor(chat_actor_subject)
    }
    ChatActorReplyWait -> {
      process.sleep(10)
      run_actor(chat_actor_subject)
    }
    ChatActorReplyDone(output) -> {
      process.send(chat_actor_subject, ChatActorMessageStop)
      output
    }
  }
}

pub fn main() -> Nil {
  let #(chat_actor_pid, chat_actor_subject) =
    make_chat_actor("Initial message is here")

  let result = run_actor(chat_actor_subject)

  case process.is_alive(chat_actor_pid), result {
    True, _ -> io.println("run_actor completed but actor is still running!")
    _, Ok(output) -> io.println(output)
    _, Error(reason) -> io.println(reason)
  }
}
