//Tests XD
import gleam/string
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
    email: Option(String),  // email address
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

// ---- encoder tests ----

pub fn flat_encoder_test() {
  let schema =
    SObject("User", [
      Field("age", "age", SInt, False),
      Field("name", "name", SString, False),
    ])

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"age\", json.int(user.age)),
    #(\"name\", json.string(user.name)),
  ])
}",
  )
}

pub fn nested_encoder_test() {
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

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"address\", address_to_json(user.address)),
    #(\"name\", json.string(user.name)),
  ])
}

pub fn address_to_json(address: Address) -> json.Json {
  json.object([
    #(\"city\", json.string(address.city)),
  ])
}",
  )
}

pub fn nullable_encoder_test() {
  let schema =
    SObject("User", [
      Field("email", "email", SNullable(SString), False),
      Field("name", "name", SString, False),
    ])

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"email\", json.nullable(user.email, json.string)),
    #(\"name\", json.string(user.name)),
  ])
}",
  )
}

pub fn list_encoder_test() {
  let schema =
    SObject("Response", [
      Field("tags", "tags", SList(SString), False),
    ])

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn response_to_json(response: Response) -> json.Json {
  json.object([
    #(\"tags\", json.array(response.tags, json.string)),
  ])
}",
  )
}

pub fn camel_case_key_preserved_in_encoder_test() {
  let schema =
    SObject("Person", [
      Field("firstName", "first_name", SString, False),
    ])

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn person_to_json(person: Person) -> json.Json {
  json.object([
    #(\"firstName\", json.string(person.first_name)),
  ])
}",
  )
}

// ---- unified module output tests ----

pub fn full_module_test() {
  let schema =
    SObject("User", [
      Field("age", "age", SInt, False),
      Field("name", "name", SString, False),
    ])

  emit.emit_module(schema, emit.default_options())
  |> should.equal(
    "import gleam/dynamic/decode
import gleam/json

pub type User {
  User(
    age: Int,
    name: String,
  )
}

pub fn user_decoder() -> decode.Decoder(User) {
  use age <- decode.field(\"age\", decode.int)
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(age:, name:))
}

pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"age\", json.int(user.age)),
    #(\"name\", json.string(user.name)),
  ])
}
",
  )
}

pub fn module_no_encoders_test() {
  let schema =
    SObject("User", [
      Field("name", "name", SString, False),
    ])

  emit.emit_module(schema, emit.EmitOptions(decoders: True, encoders: False))
  |> should.equal(
    "import gleam/dynamic/decode

pub type User {
  User(
    name: String,
  )
}

pub fn user_decoder() -> decode.Decoder(User) {
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(name:))
}
",
  )
}

pub fn module_no_decoders_test() {
  let schema =
    SObject("User", [
      Field("name", "name", SString, False),
    ])

  emit.emit_module(schema, emit.EmitOptions(decoders: False, encoders: True))
  |> should.equal(
    "import gleam/json

pub type User {
  User(
    name: String,
  )
}

pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"name\", json.string(user.name)),
  ])
}
",
  )
}

pub fn module_with_option_import_test() {
  let schema =
    SObject("User", [
      Field("email", "email", SNullable(SString), False),
      Field("name", "name", SString, False),
    ])

  emit.emit_module(schema, emit.default_options())
  |> should.equal(
    "import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

pub type User {
  User(
    email: Option(String),  // email address
    name: String,
  )
}

pub fn user_decoder() -> decode.Decoder(User) {
  use email <- decode.field(\"email\", decode.optional(decode.string))
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(email:, name:))
}

pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"email\", json.nullable(user.email, json.string)),
    #(\"name\", json.string(user.name)),
  ])
}
",
  )
}

pub fn empty_object_encoder_test() {
  let schema = SObject("Empty", [])

  emit.emit_encoders(schema)
  |> should.equal(
    "pub fn empty_to_json(_empty: Empty) -> json.Json {
  json.object([])
}",
  )
}

// ---- type hint comment tests ----

pub fn datetime_hint_test() {
  let schema =
    SObject("Event", [
      Field("created_at", "created_at", SString, False),
      Field("name", "name", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Event {
  Event(
    created_at: String,  // ISO 8601 datetime
    name: String,
  )
}",
  )
}

pub fn url_hint_test() {
  let schema =
    SObject("Link", [
      Field("avatar_url", "avatar_url", SString, False),
      Field("homepage", "homepage", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Link {
  Link(
    avatar_url: String,  // URL
    homepage: String,  // URL
  )
}",
  )
}

pub fn id_hint_test() {
  let schema =
    SObject("Item", [
      Field("id", "id", SString, False),
      Field("user_id", "user_id", SString, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Item {
  Item(
    id: String,  // identifier
    user_id: String,  // identifier
  )
}",
  )
}

pub fn no_hint_on_non_string_test() {
  let schema =
    SObject("Settings", [
      Field("email", "email", schema.SBool, False),
    ])

  emit.emit_types(schema)
  |> should.equal(
    "pub type Settings {
  Settings(
    email: Bool,
  )
}",
  )
}

// ---- top-level non-object module tests ----

pub fn toplevel_list_module_test() {
  let schema = SList(SInt)

  emit.emit_module(schema, emit.default_options())
  |> should.equal(
    "import gleam/dynamic/decode

/// The top-level JSON value is: List(Int)

/// Decoder for the top-level value
pub fn decoder() -> decode.Decoder(List(Int)) {
  decode.list(decode.int)
}
",
  )
}

pub fn toplevel_list_of_objects_module_test() {
  let schema =
    SList(
      SObject("User", [
        Field("name", "name", SString, False),
      ]),
    )

  emit.emit_module(schema, emit.default_options())
  |> should.equal(
    "import gleam/dynamic/decode
import gleam/json

/// The top-level JSON value is: List(User)

pub type User {
  User(
    name: String,
  )
}

/// Decoder for the top-level value
pub fn decoder() -> decode.Decoder(List(User)) {
  decode.list(user_decoder())
}

pub fn user_decoder() -> decode.Decoder(User) {
  use name <- decode.field(\"name\", decode.string)
  decode.success(User(name:))
}

pub fn user_to_json(user: User) -> json.Json {
  json.object([
    #(\"name\", json.string(user.name)),
  ])
}
",
  )
}

pub fn toplevel_string_module_test() {
  let schema = SString

  emit.emit_module(schema, emit.default_options())
  |> should.equal(
    "import gleam/dynamic/decode

/// The top-level JSON value is: String

/// Decoder for the top-level value
pub fn decoder() -> decode.Decoder(String) {
  decode.string
}
",
  )
}

// ---- type name deduplication tests ----

pub fn duplicate_type_names_get_suffixed_test() {
  // Two nested objects both named "Data" but with different fields
  let schema =
    SObject("Root", [
      Field(
        "data",
        "data",
        SObject("Data", [
          Field("id", "id", SInt, False),
          Field("name", "name", SString, False),
        ]),
        False,
      ),
      Field(
        "meta",
        "meta",
        SObject("Meta", [
          Field(
            "data",
            "data",
            SObject("Data", [Field("id", "id", SInt, False)]),
            False,
          ),
        ]),
        False,
      ),
    ])

  let output = emit.emit_module(schema, emit.default_options())
  // The first Data keeps its name, the second becomes Data2
  should.be_true(string.contains(output, "pub type Data {"))
  should.be_true(string.contains(output, "pub type Data2 {"))
  should.be_true(string.contains(output, "data: Data2,"))
  // No duplicate type definitions
  should.equal(count_occurrences(output, "pub type Data {"), 1)
}

pub fn same_structure_types_share_name_test() {
  // Two nested objects both named "Data" with identical fields — should NOT be renamed
  let schema =
    SObject("Root", [
      Field("a", "a", SObject("Data", [Field("id", "id", SInt, False)]), False),
      Field("b", "b", SObject("Data", [Field("id", "id", SInt, False)]), False),
    ])

  let output = emit.emit_module(schema, emit.default_options())
  should.equal(count_occurrences(output, "pub type Data {"), 1)
  should.be_false(string.contains(output, "Data2"))
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  do_count(haystack, needle, 0)
}

fn do_count(haystack: String, needle: String, acc: Int) -> Int {
  case string.split_once(haystack, needle) {
    Ok(#(_, rest)) -> do_count(rest, needle, acc + 1)
    Error(_) -> acc
  }
}
