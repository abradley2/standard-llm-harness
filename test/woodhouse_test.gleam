import gleam/bit_array
import gleam/bytes_tree
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import woodhouse

pub fn main() -> Nil {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  let name = "Joe"
  let greeting = "Hello, " <> name <> "!"

  assert greeting == "Hello, Joe!"
}
