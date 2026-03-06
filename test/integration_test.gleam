// Smoke tests against real-world JSON files in test_data/
// Verifies the full pipeline doesn't crash and produces reasonable output.

import gleam/string
import gleeunit
import gleeunit/should
import json2gleam/emit
import json2gleam/infer
import json2gleam/schema.{SObject}
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn simple_user_smoke_test() {
  let assert Ok(json) = simplifile.read("test_data/simple_user.json")
  let assert Ok(schema) = infer.infer_schema(json, "User")
  let assert SObject("User", fields) = schema
  // simple_user.json has id, name, email, active, score
  list.length(fields) |> should.equal(5)

  let code = emit.emit_module(schema, emit.default_options())
  code |> string.contains("pub type User") |> should.be_true()
  code |> string.contains("user_decoder") |> should.be_true()
  code |> string.contains("user_to_json") |> should.be_true()
}

pub fn user_smoke_test() {
  let assert Ok(json) = simplifile.read("test_data/user.json")
  let assert Ok(schema) = infer.infer_schema(json, "User")
  let assert SObject("User", _) = schema

  let code = emit.emit_module(schema, emit.default_options())
  code |> string.contains("pub type User") |> should.be_true()
  // Should have nested types
  code |> string.contains("pub type Profile") |> should.be_true()
}

pub fn github_smoke_test() {
  let assert Ok(json) = simplifile.read("test_data/github.json")
  let assert Ok(schema) = infer.infer_schema(json, "GitHubRepo")

  let code = emit.emit_module(schema, emit.default_options())
  code |> string.contains("pub type") |> should.be_true()
  code |> string.contains("decoder") |> should.be_true()
}

pub fn stripe_event_smoke_test() {
  let assert Ok(json) = simplifile.read("test_data/stripe_event.json")
  let assert Ok(schema) = infer.infer_schema(json, "StripeEvent")
  let assert SObject("StripeEvent", _) = schema

  let code = emit.emit_module(schema, emit.default_options())
  code |> string.contains("pub type StripeEvent") |> should.be_true()
  code |> string.contains("stripe_event_decoder") |> should.be_true()
  code |> string.contains("stripe_event_to_json") |> should.be_true()
}

pub fn all_files_no_crash_with_options_test() {
  // Verify all files work with non-default options too
  let files = [
    "test_data/simple_user.json",
    "test_data/user.json",
    "test_data/github.json",
    "test_data/stripe_event.json",
  ]
  let opts =
    infer.InferOptions(singularize: False, numbers_as_float: True)

  list.each(files, fn(path) {
    let assert Ok(json) = simplifile.read(path)
    let assert Ok(schema) =
      infer.infer_schema_with_options(json, "Root", opts)

    let code =
      emit.emit_module(schema, emit.EmitOptions(decoders: True, encoders: True))
    // Should produce non-empty valid-looking Gleam code
    { string.length(code) > 0 } |> should.be_true()
    code |> string.contains("pub type") |> should.be_true()
  })
}

import gleam/list
