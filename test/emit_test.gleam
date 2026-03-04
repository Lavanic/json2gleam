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

// ---- decoder tests ----

pub fn flat_decoder_test() {
  let schema =
    SObject("User", [
      Field("age", "age", SInt, False),
      Field("name", "name", SString, False),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn user_decoder() -> decode.Decoder(User) {
  use age <- decode.field(\"age\", decode.int)
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(age:, name:))
}",
  )
}

pub fn nested_decoder_test() {
  let schema =
    SObject("User", [
      Field(
        "address",
        "address",
        SObject("Address", [
          Field("city", "city", SString, False),
        ]),
        False,
      ),
      Field("name", "name", SString, False),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn user_decoder() -> decode.Decoder(User) {
  use address <- decode.field(\"address\", address_decoder())
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(address:, name:))
}

pub fn address_decoder() -> decode.Decoder(Address) {
  use city <- decode.field(\"city\", decode.string)
  decode.success(Address(city:))
}",
  )
}

pub fn nullable_decoder_test() {
  let schema =
    SObject("User", [
      Field("email", "email", SNullable(SString), False),
      Field("name", "name", SString, False),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn user_decoder() -> decode.Decoder(User) {
  use email <- decode.field(\"email\", decode.optional(decode.string))
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(email:, name:))
}",
  )
}

pub fn optional_decoder_test() {
  let schema =
    SObject("Config", [
      Field("debug", "debug", SString, True),
      Field("name", "name", SString, False),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn config_decoder() -> decode.Decoder(Config) {
  use debug <- decode.optional_field(\"debug\", option.None, decode.optional(decode.string))
  use name <- decode.field(\"name\", decode.string)
  decode.success(Config(debug:, name:))
}",
  )
}

pub fn optional_nullable_decoder_test() {
  let schema =
    SObject("Thing", [
      Field("maybe", "maybe", SNullable(SString), True),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn thing_decoder() -> decode.Decoder(Thing) {
  use maybe <- decode.optional_field(\"maybe\", option.None, decode.optional(decode.string))
  decode.success(Thing(maybe:))
}",
  )
}

pub fn list_decoder_test() {
  let schema =
    SObject("Response", [
      Field("tags", "tags", SList(SString), False),
      Field(
        "items",
        "items",
        SList(SObject("Item", [Field("id", "id", SInt, False)])),
        False,
      ),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn response_decoder() -> decode.Decoder(Response) {
  use tags <- decode.field(\"tags\", decode.list(decode.string))
  use items <- decode.field(\"items\", decode.list(item_decoder()))
  decode.success(Response(tags:, items:))
}

pub fn item_decoder() -> decode.Decoder(Item) {
  use id <- decode.field(\"id\", decode.int)
  decode.success(Item(id:))
}",
  )
}

pub fn camel_case_key_preserved_in_decoder_test() {
  let schema =
    SObject("Person", [
      Field("firstName", "first_name", SString, False),
    ])

  // decoder should use the original JSON key "firstName" not the gleam name
  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn person_decoder() -> decode.Decoder(Person) {
  use first_name <- decode.field(\"firstName\", decode.string)
  decode.success(Person(first_name:))
}",
  )
}

pub fn dynamic_decoder_test() {
  let schema =
    SObject("Data", [
      Field("unknown", "unknown", SDynamic, False),
    ])

  emit.emit_decoders(schema)
  |> should.equal(
    "pub fn data_decoder() -> decode.Decoder(Data) {
  use unknown <- decode.field(\"unknown\", decode.dynamic)
  decode.success(Data(unknown:))
}",
  )
}
