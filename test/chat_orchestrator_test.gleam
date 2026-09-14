import chat_orchestrator
import gleeunit
import ollama
import tool

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn run_uses_injected_chat_invoker_test() {
  let #(_orchestrator_pid, orchestrator_events) =
    chat_orchestrator.start(
      "Test prompt",
      fn(_messages) { Ok(ollama.OllamaChatResponse("Test response", [])) },
      fn(_tool_call) { tool.ToolResponse("unused", "{}") },
    )

  assert Ok("Test response") == chat_orchestrator.run(orchestrator_events)
}

pub fn run_returns_injected_chat_invoker_error_test() {
  let #(_orchestrator_pid, orchestrator_events) =
    chat_orchestrator.start(
      "Test prompt",
      fn(_messages) { Error("Model unavailable") },
      fn(_tool_call) { tool.ToolResponse("unused", "{}") },
    )

  assert Error("Model unavailable")
    == chat_orchestrator.run(orchestrator_events)
}

pub fn run_uses_injected_tool_resolver_test() {
  let #(_orchestrator_pid, orchestrator_events) =
    chat_orchestrator.start(
      "Test prompt",
      fn(messages) {
        case messages {
          [_, _, ollama.ToolMessage("test_tool", _)] ->
            Ok(ollama.OllamaChatResponse("Tool result received", []))
          [_, _, ollama.ToolMessage(_, _)] -> Error("Unexpected tool response")
          _ -> Ok(ollama.OllamaChatResponse("", [tool.Invalid]))
        }
      },
      fn(_tool_call) { tool.ToolResponse("test_tool", "{}") },
    )

  assert Ok("Tool result received")
    == chat_orchestrator.run(orchestrator_events)
}
