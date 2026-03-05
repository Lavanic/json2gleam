//Tests XD
import gleeunit
import gleeunit/should
import json2gleam/infer
import json2gleam/schema.{
  Field, SBool, SDynamic, SFloat, SInt, SList, SNullable, SObject, SString,
}

pub fn main() {
  gleeunit.main()
}

// --- basic primitives in a flat object ---

pub fn flat_object_with_primitives_test() {
  let json =
    "{\"name\": \"Lucy\", \"age\": 30, \"score\": 9.5, \"active\": true}"

  let assert Ok(schema) = infer.infer_schema(json, "User")

  schema
  |> should.equal(
    SObject("User", [
      Field("active", "active", SBool, False),
      Field("age", "age", SInt, False),
      Field("name", "name", SString, False),
      Field("score", "score", SFloat, False),
    ]),
  )
}

// --- nested objects ---

pub fn nested_object_test() {
  let json =
    "{\"user\": {\"name\": \"Lucy\", \"address\": {\"city\": \"London\"}}}"

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema
  |> should.equal(
    SObject("Root", [
      Field(
        "user",
        "user",
        SObject("User", [
          Field(
            "address",
            "address",
            SObject("Address", [Field("city", "city", SString, False)]),
            False,
          ),
          Field("name", "name", SString, False),
        ]),
        False,
      ),
    ]),
  )
}

// --- arrays ---

pub fn array_of_primitives_test() {
  let json = "{\"tags\": [\"gleam\", \"erlang\"]}"

  let assert Ok(schema) = infer.infer_schema(json, "Config")

  schema
  |> should.equal(
    SObject("Config", [
      Field("tags", "tags", SList(SString), False),
    ]),
  )
}

pub fn array_of_objects_test() {
  let json = "{\"items\": [{\"id\": 1, \"name\": \"thing\"}]}"

  let assert Ok(schema) = infer.infer_schema(json, "Response")

  schema
  |> should.equal(
    SObject("Response", [
      Field(
        "items",
        "items",
        SList(
          SObject("Item", [
            Field("id", "id", SInt, False),
            Field("name", "name", SString, False),
          ]),
        ),
        False,
      ),
    ]),
  )
}

pub fn empty_array_test() {
  let json = "{\"things\": []}"

  let assert Ok(schema) = infer.infer_schema(json, "Data")

  schema
  |> should.equal(
    SObject("Data", [
      Field("things", "things", SList(SDynamic), False),
    ]),
  )
}

// --- nulls ---

pub fn null_field_test() {
  let json = "{\"name\": \"Lucy\", \"email\": null}"

  let assert Ok(schema) = infer.infer_schema(json, "User")

  schema
  |> should.equal(
    SObject("User", [
      Field("email", "email", SNullable(SDynamic), False),
      Field("name", "name", SString, False),
    ]),
  )
}

// --- top-level array ---

pub fn top_level_array_test() {
  let json = "[{\"id\": 1}, {\"id\": 2}]"

  let assert Ok(schema) = infer.infer_schema(json, "Items")

  schema
  |> should.equal(SList(SObject("Item", [Field("id", "id", SInt, False)])))
}

// --- camelCase → snake_case conversion ---

pub fn camel_case_keys_test() {
  let json = "{\"firstName\": \"Lucy\", \"lastName\": \"Gleam\"}"

  let assert Ok(schema) = infer.infer_schema(json, "Person")

  schema
  |> should.equal(
    SObject("Person", [
      Field("firstName", "first_name", SString, False),
      Field("lastName", "last_name", SString, False),
    ]),
  )
}

pub fn already_snake_case_keys_test() {
  let json = "{\"first_name\": \"Lucy\"}"

  let assert Ok(schema) = infer.infer_schema(json, "Person")

  schema
  |> should.equal(
    SObject("Person", [
      Field("first_name", "first_name", SString, False),
    ]),
  )
}

// --- error cases ---

pub fn empty_input_test() {
  let assert Error(infer.EmptyInput) = infer.infer_schema("", "Anything")
  let assert Error(infer.EmptyInput) = infer.infer_schema("   ", "Anything")
}

pub fn invalid_json_test() {
  let assert Error(infer.JsonParseError(_)) =
    infer.infer_schema("{not json", "Oops")
}

// --- edge cases: reserved words and weird keys ---

pub fn reserved_word_field_test() {
  let json = "{\"type\": \"admin\", \"let\": 42}"

  let assert Ok(schema) = infer.infer_schema(json, "Thing")

  schema
  |> should.equal(
    SObject("Thing", [
      Field("let", "let_", SInt, False),
      Field("type", "type_", SString, False),
    ]),
  )
}

pub fn numeric_start_key_test() {
  let json = "{\"3d_mode\": true}"

  let assert Ok(schema) = infer.infer_schema(json, "Settings")

  // should prepend field_ since it starts with a digit
  schema
  |> should.equal(
    SObject("Settings", [
      Field("3d_mode", "field_3d_mode", SBool, False),
    ]),
  )
}

// --- top-level primitive (just a string/number, not an object) ---

pub fn top_level_string_test() {
  let json = "\"just a string\""

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema |> should.equal(SString)
}

pub fn top_level_number_test() {
  let json = "42"

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema |> should.equal(SInt)
}

// --- array merging: objects with different fields ---

pub fn array_merge_optional_fields_test() {
  let json = "[{\"id\": 1, \"name\": \"a\"}, {\"id\": 2, \"extra\": true}]"

  let assert Ok(schema) = infer.infer_schema(json, "Items")

  schema
  |> should.equal(
    SList(
      SObject("Item", [
        Field("extra", "extra", SBool, True),
        Field("id", "id", SInt, False),
        Field("name", "name", SString, True),
      ]),
    ),
  )
}

pub fn array_merge_null_refinement_test() {
  // first element has null email, second has a string
  let json = "[{\"email\": null}, {\"email\": \"a@b.com\"}]"

  let assert Ok(schema) = infer.infer_schema(json, "Users")

  schema
  |> should.equal(
    SList(
      SObject("User", [
        Field("email", "email", SNullable(SString), False),
      ]),
    ),
  )
}

pub fn array_merge_nested_objects_test() {
  // two objects with same nested structure but different nested fields
  let json =
    "[{\"addr\": {\"city\": \"A\"}}, {\"addr\": {\"city\": \"B\", \"zip\": \"12345\"}}]"

  let assert Ok(schema) = infer.infer_schema(json, "People")

  schema
  |> should.equal(
    SList(
      SObject("People", [
        Field(
          "addr",
          "addr",
          SObject("Addr", [
            Field("city", "city", SString, False),
            Field("zip", "zip", SString, True),
          ]),
          False,
        ),
      ]),
    ),
  )
}

// --- field name deduplication ---

pub fn duplicate_field_names_test() {
  let json = "{\"$ref\": \"a\", \"ref\": \"b\"}"

  let assert Ok(schema) = infer.infer_schema(json, "Thing")

  schema
  |> should.equal(
    SObject("Thing", [
      Field("$ref", "ref", SString, False),
      Field("ref", "ref_2", SString, False),
    ]),
  )
}

// --- merge_schemas unit tests ---

pub fn merge_int_float_test() {
  infer.merge_schemas(SInt, SFloat)
  |> should.equal(SFloat)
}

pub fn merge_null_refine_test() {
  infer.merge_schemas(SNullable(SDynamic), SString)
  |> should.equal(SNullable(SString))
}

pub fn merge_incompatible_test() {
  infer.merge_schemas(SString, SInt)
  |> should.equal(SDynamic)
}

pub fn merge_nullable_non_nullable_test() {
  infer.merge_schemas(SNullable(SString), SString)
  |> should.equal(SNullable(SString))
}

pub fn merge_lists_test() {
  infer.merge_schemas(SList(SInt), SList(SFloat))
  |> should.equal(SList(SFloat))
}

// --- top-level edge cases ---

pub fn top_level_null_test() {
  let json = "null"

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema |> should.equal(SNullable(SDynamic))
}

pub fn top_level_bool_test() {
  let json = "true"

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema |> should.equal(SBool)
}

pub fn top_level_float_test() {
  let json = "3.14"

  let assert Ok(schema) = infer.infer_schema(json, "Root")

  schema |> should.equal(SFloat)
}
