//Tests XD
import gleeunit
import gleeunit/should
import json2gleam/emit
import json2gleam/schema.{
  Field, SDynamic, SFloat, SInt, SList, SNullable, SObject, SString,
}

pub fn main() {
  gleeunit.main()
}

// --- simple flat type ---

pub fn flat_type_test() {
  let schema =
    SObject("User", [
      Field("age", "age", SInt, False),
      Field("name", "name", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type User {
  User(
    age: Int,
    name: String,
  )
}",
  )
}

// --- nested types should produce multiple type blocks ---

pub fn nested_types_test() {
  let schema =
    SObject("User", [
      Field(
        "address",
        "address",
        SObject("Address", [
          Field("city", "city", SString, False),
          Field("zip", "zip", SString, False),
        ]),
        False,
      ),
      Field("name", "name", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type User {
  User(
    address: Address,
    name: String,
  )
}

pub type Address {
  Address(
    city: String,
    zip: String,
  )
}",
  )
}

// --- nullable fields should bring in the Option import ---

pub fn nullable_field_test() {
  let schema =
    SObject("User", [
      Field("email", "email", SNullable(SString), False),
      Field("name", "name", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "import gleam/option.{type Option}

pub type User {
  User(
    email: Option(String),
    name: String,
  )
}",
  )
}

// --- optional field (from multi-sample merge) ---

pub fn optional_field_test() {
  let schema =
    SObject("Config", [
      Field("debug", "debug", SString, True),
      Field("name", "name", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "import gleam/option.{type Option}

pub type Config {
  Config(
    debug: Option(String),
    name: String,
  )
}",
  )
}

// --- optional + nullable collapses to single Option ---

pub fn optional_nullable_no_double_wrap_test() {
  let schema =
    SObject("Thing", [
      Field("maybe", "maybe", SNullable(SString), True),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "import gleam/option.{type Option}

pub type Thing {
  Thing(
    maybe: Option(String),
  )
}",
  )
}

// --- list of objects should emit the inner type ---

pub fn list_of_objects_test() {
  let schema =
    SObject("Response", [
      Field(
        "items",
        "items",
        SList(
          SObject("Item", [
            Field("id", "id", SInt, False),
          ]),
        ),
        False,
      ),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Response {
  Response(
    items: List(Item),
  )
}

pub type Item {
  Item(
    id: Int,
  )
}",
  )
}

// --- Dynamic fields bring in the dynamic import ---

pub fn dynamic_field_test() {
  let schema =
    SObject("Data", [
      Field("stuff", "stuff", SList(SDynamic), False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "import gleam/dynamic.{type Dynamic}

pub type Data {
  Data(
    stuff: List(Dynamic),
  )
}",
  )
}

// --- both Option and Dynamic imports when needed ---

pub fn both_imports_test() {
  let schema =
    SObject("Data", [
      Field("maybe", "maybe", SNullable(SDynamic), False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

pub type Data {
  Data(
    maybe: Option(Dynamic),
  )
}",
  )
}

// --- all the primitive types ---

pub fn all_primitives_test() {
  let schema =
    SObject("Everything", [
      Field("active", "active", schema.SBool, False),
      Field("count", "count", SInt, False),
      Field("name", "name", SString, False),
      Field("score", "score", SFloat, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Everything {
  Everything(
    active: Bool,
    count: Int,
    name: String,
    score: Float,
  )
}",
  )
}
