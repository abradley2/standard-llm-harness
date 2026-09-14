import gleam/erlang/process.{type Pid, type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Next}
import ollama.{
  type ChatMessage, type OllamaChatResponse, AssistantMessage,
  OllamaChatResponse, ToolMessage, UserMessage,
}
import tool.{type ToolCall, type ToolResponse}

pub type ChatInvoker =
  fn(List(ChatMessage)) -> Result(OllamaChatResponse, String)

pub type ToolResolver =
  fn(ToolCall) -> ToolResponse

pub type ConversationState {
  ConversationState(
    error: Option(String),
    conversation_messages: List(ChatMessage),
    pending_tool_workers: List(Pid),
    invoke_chat: ChatInvoker,
    resolve_tool_call: ToolResolver,
  )
}

pub type OrchestratorEvent {
  Advance(outcome_subject: Subject(OrchestrationOutcome))
  ScheduleToolCalls(
    orchestrator_events: Subject(OrchestratorEvent),
    tool_calls: List(ToolCall),
  )
  ToolWorkerCompleted(pid: Pid, tool_result: Result(ToolResponse, String))
  Shutdown
}

pub type OrchestrationOutcome {
  RunToolCalls(tool_calls: List(ToolCall))
  AwaitToolWorkers
  Completed(output: Result(String, String))
}

pub fn handle_event(
  state: ConversationState,
  event: OrchestratorEvent,
) -> Next(ConversationState, OrchestratorEvent) {
  case state.error, event {
    _, ScheduleToolCalls(orchestrator_events, tool_calls) -> {
      let worker_pids =
        tool_calls
        |> list.map(spawn_tool_worker(
          orchestrator_events,
          state.resolve_tool_call,
          _,
        ))

      actor.continue(
        ConversationState(..state, pending_tool_workers: worker_pids),
      )
    }
    _, ToolWorkerCompleted(_, Error(_tool_execution_error)) -> {
      actor.continue(
        ConversationState(..state, error: Some("This is an error!")),
      )
    }
    _, ToolWorkerCompleted(completed_worker_pid, Ok(tool_response)) -> {
      state.pending_tool_workers
      |> list.fold(
        ConversationState(..state, pending_tool_workers: []),
        fn(previous_state, pending_worker_pid) {
          case completed_worker_pid == pending_worker_pid {
            True ->
              ConversationState(
                ..previous_state,
                conversation_messages: previous_state.conversation_messages
                  |> list.append([
                    ToolMessage(
                      tool_response.tool_name,
                      tool_response.json_content,
                    ),
                  ]),
              )
            False ->
              ConversationState(
                ..previous_state,
                pending_tool_workers: previous_state.pending_tool_workers
                  |> list.append([pending_worker_pid]),
              )
          }
        },
      )
      |> actor.continue
    }
    Some(_err), Advance(outcome_subject) -> {
      process.send(outcome_subject, Completed(Error("Some error happend")))
      actor.continue(state)
    }
    None, Advance(outcome_subject) -> {
      case state.pending_tool_workers {
        [] -> {
          case state.invoke_chat(state.conversation_messages) {
            Ok(OllamaChatResponse(assistant_message, [])) -> {
              process.send(outcome_subject, Completed(Ok(assistant_message)))
              actor.continue(state)
            }
            Ok(OllamaChatResponse(assistant_message, tool_calls)) -> {
              process.send(outcome_subject, RunToolCalls(tool_calls))
              actor.continue(
                ConversationState(
                  ..state,
                  conversation_messages: state.conversation_messages
                    |> list.append([
                      AssistantMessage(assistant_message, tool_calls),
                    ]),
                ),
              )
            }
            Error(reason) -> {
              process.send(outcome_subject, Completed(Error(reason)))
              actor.continue(ConversationState(..state, error: Some(reason)))
            }
          }
        }
        _ -> {
          process.send(outcome_subject, AwaitToolWorkers)
          actor.continue(state)
        }
      }
    }

    _, Shutdown -> actor.stop()
  }
}

pub fn start(
  initial_user_prompt: String,
  invoke_chat: ChatInvoker,
  resolve_tool_call: ToolResolver,
) -> #(Pid, Subject(OrchestratorEvent)) {
  let assert Ok(orchestrator) =
    actor.new(ConversationState(
      error: None,
      conversation_messages: [UserMessage(initial_user_prompt)],
      pending_tool_workers: [],
      invoke_chat: invoke_chat,
      resolve_tool_call: resolve_tool_call,
    ))
    |> actor.on_message(handle_event)
    |> actor.start

  let event_subject = orchestrator.data

  #(orchestrator.pid, event_subject)
}

pub fn spawn_tool_worker(
  orchestrator_events: Subject(OrchestratorEvent),
  resolve_tool_call: ToolResolver,
  tool_call: ToolCall,
) -> Pid {
  process.spawn(fn() {
    process.send(
      orchestrator_events,
      ToolWorkerCompleted(process.self(), Ok(resolve_tool_call(tool_call))),
    )
  })
}

pub fn run(
  orchestrator_events: Subject(OrchestratorEvent),
) -> Result(String, String) {
  let outcome = process.call(orchestrator_events, 1000 * 60 * 5, Advance)

  case outcome {
    RunToolCalls(tool_calls) -> {
      process.send(
        orchestrator_events,
        ScheduleToolCalls(orchestrator_events, tool_calls),
      )
      run(orchestrator_events)
    }
    AwaitToolWorkers -> {
      process.sleep(10)
      run(orchestrator_events)
    }
    Completed(output) -> {
      process.send(orchestrator_events, Shutdown)
      output
    }
  }
}

pub fn main() -> Nil {
  let #(orchestrator_pid, orchestrator_events) =
    start(
      "Initial message is here",
      ollama.invoke_ollama_chat,
      tool.resolve_tool_call,
    )

  let result = run(orchestrator_events)

  case process.is_alive(orchestrator_pid), result {
    True, _ -> io.println("run completed but orchestrator is still running!")
    _, Ok(output) -> io.println(output)
    _, Error(reason) -> io.println(reason)
  }
}
