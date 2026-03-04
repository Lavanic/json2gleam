// Code emitter
import gleam/list
import gleam/string
import gleam/string_tree
import json2gleam/schema.{
  type Field, type Schema, SBool, SDynamic, SFloat, SInt, SList, SNullable,
  SObject, SString,
}

/// Emit all type definitions for a schema.
/// Walks the tree finds every SObject and spits out a
/// `pub type ...` block for each one.
pub fn emit_types(schema: Schema) -> String {
  let types = collect_object_types(schema)
  let needs_option = uses_option(schema)
  let needs_dynamic = uses_dynamic(schema)

  let imports = build_type_imports(needs_option, needs_dynamic)

  let type_defs =
    types
    |> list.map(emit_single_type)
    |> string.join("\n\n")

  case imports {
    "" -> type_defs
    _ -> imports <> "\n\n" <> type_defs
  }
}

/// One `pub type Foo { Foo(...) }` block
fn emit_single_type(obj: #(String, List(Field))) -> String {
  let #(name, fields) = obj

  case fields {
    [] -> "pub type " <> name <> " {\n  " <> name <> "\n}"
    _ -> {
      let field_lines =
        fields
        |> list.map(fn(f) { "    " <> f.gleam_name <> ": " <> type_string(f) })
        |> string.join(",\n")

      "pub type "
      <> name
      <> " {\n  "
      <> name
      <> "(\n"
      <> field_lines
      <> ",\n  )\n}"
    }
  }
}

/// Figure out the Gleam type string for a field,
/// taking into account optional + nullable
fn type_string(field: Field) -> String {
  case field.optional, field.schema {
    // optional fields always get wrapped in Option, and if
    // it's also nullable we collapse to a single Option layer
    True, SNullable(inner) -> "Option(" <> schema_type_string(inner) <> ")"
    True, other -> "Option(" <> schema_type_string(other) <> ")"
    False, s -> schema_type_string(s)
  }
}

/// Map a Schema to its Gleam type string
pub fn schema_type_string(schema: Schema) -> String {
  case schema {
    SString -> "String"
    SInt -> "Int"
    SFloat -> "Float"
    SBool -> "Bool"
    SDynamic -> "Dynamic"
    SNullable(inner) -> "Option(" <> schema_type_string(inner) <> ")"
    SList(inner) -> "List(" <> schema_type_string(inner) <> ")"
    SObject(name, _) -> name
  }
}

/// Walk the schema and collect all (name, fields) pairs for objects
/// Root type comes first, then nested types after.
fn collect_object_types(schema: Schema) -> List(#(String, List(Field))) {
  collect_from_schema(schema)
}

fn collect_from_field(field: Field) -> List(#(String, List(Field))) {
  collect_from_schema(field.schema)
}

/// dig into a schema looking for SObjects
fn collect_from_schema(schema: Schema) -> List(#(String, List(Field))) {
  case schema {
    SObject(name, fields) -> {
      let nested =
        fields
        |> list.flat_map(collect_from_field)
      [#(name, fields), ..nested]
    }
    SList(inner) -> collect_from_schema(inner)
    SNullable(inner) -> collect_from_schema(inner)
    _ -> []
  }
}

/// does any part of the schema need Option?
fn uses_option(schema: Schema) -> Bool {
  case schema {
    SNullable(_) -> True
    SObject(_, fields) ->
      list.any(fields, fn(f) { f.optional || uses_option(f.schema) })
    SList(inner) -> uses_option(inner)
    _ -> False
  }
}

/// does any part of the schema use Dynamic?
fn uses_dynamic(schema: Schema) -> Bool {
  case schema {
    SDynamic -> True
    SNullable(inner) -> uses_dynamic(inner)
    SObject(_, fields) -> list.any(fields, fn(f) { uses_dynamic(f.schema) })
    SList(inner) -> uses_dynamic(inner)
    _ -> False
  }
}

/// only import what's actually needed
fn build_type_imports(needs_option: Bool, needs_dynamic: Bool) -> String {
  let imports = []
  let imports = case needs_dynamic {
    True -> ["import gleam/dynamic.{type Dynamic}", ..imports]
    False -> imports
  }
  let imports = case needs_option {
    True -> ["import gleam/option.{type Option}", ..imports]
    False -> imports
  }
  imports
  |> list.sort(string.compare)
  |> string.join("\n")
}

// decoder 

/// Emit decoder functions for every obj type in the schema
/// Uses the modern `use field <- decode.field(...)` style.
pub fn emit_decoders(schema: Schema) -> String {
  let types = collect_object_types(schema)

  types
  |> list.map(emit_single_decoder)
  |> string.join("\n\n")
}

/// one decoder function for one object type
fn emit_single_decoder(obj: #(String, List(Field))) -> String {
  let #(name, fields) = obj
  let fn_name = snake_case_name(name)
  let st = string_tree.new()

  let st =
    st
    |> string_tree.append("pub fn " <> fn_name <> "_decoder()")
    |> string_tree.append(" -> decode.Decoder(" <> name <> ") {\n")

  // each field gets a `use field_name <- decode.field/optional_field(...)` line
  let st =
    list.fold(fields, st, fn(acc, f) {
      acc |> string_tree.append(emit_field_decoder_line(f))
    })

  // final line: decode.success(TypeName(field1:, field2:, ...))
  let field_shorthand =
    fields
    |> list.map(fn(f) { f.gleam_name <> ":" })
    |> string.join(", ")

  st
  |> string_tree.append(
    "  decode.success(" <> name <> "(" <> field_shorthand <> "))\n}",
  )
  |> string_tree.to_string()
}

/// Emit one `use field <- decode.field("key", decoder)` line
fn emit_field_decoder_line(field: Field) -> String {
  case field.optional, field.schema {
    // optional + nullable: use optional_field with decode.optional inside
    True, SNullable(inner) ->
      "  use "
      <> field.gleam_name
      <> " <- decode.optional_field(\""
      <> field.json_key
      <> "\", option.None, decode.optional("
      <> decoder_for_schema(inner)
      <> "))\n"

    // just optional (field might be missing, but when present it's not null)
    True, other ->
      "  use "
      <> field.gleam_name
      <> " <- decode.optional_field(\""
      <> field.json_key
      <> "\", option.None, decode.optional("
      <> decoder_for_schema(other)
      <> "))\n"

    // nullable but always present
    False, SNullable(inner) ->
      "  use "
      <> field.gleam_name
      <> " <- decode.field(\""
      <> field.json_key
      <> "\", decode.optional("
      <> decoder_for_schema(inner)
      <> "))\n"

    // normal required field
    False, other ->
      "  use "
      <> field.gleam_name
      <> " <- decode.field(\""
      <> field.json_key
      <> "\", "
      <> decoder_for_schema(other)
      <> ")\n"
  }
}

/// Map a schema to the decoder expression string
fn decoder_for_schema(schema: Schema) -> String {
  case schema {
    SString -> "decode.string"
    SInt -> "decode.int"
    SFloat -> "decode.float"
    SBool -> "decode.bool"
    SDynamic -> "decode.dynamic"
    SNullable(inner) -> "decode.optional(" <> decoder_for_schema(inner) <> ")"
    SList(inner) -> "decode.list(" <> decoder_for_schema(inner) <> ")"
    SObject(name, _) -> snake_case_name(name) <> "_decoder()"
  }
}

/// turn "UserProfile" into "user_profile" for function names
fn snake_case_name(pascal_name: String) -> String {
  // walk the string and insert _ before each uppercase letter (except the first)
  pascal_name
  |> string.to_graphemes()
  |> do_snake_case([], True)
  |> list.reverse()
  |> string.concat()
  |> string.lowercase()
}

fn do_snake_case(
  chars: List(String),
  acc: List(String),
  is_first: Bool,
) -> List(String) {
  case chars {
    [] -> acc
    [c, ..rest] -> {
      case is_uppercase(c), is_first {
        True, True -> do_snake_case(rest, [c, ..acc], False)
        True, False -> do_snake_case(rest, [c, "_", ..acc], False)
        _, _ -> do_snake_case(rest, [c, ..acc], False)
      }
    }
  }
}

fn is_uppercase(c: String) -> Bool {
  case c {
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}

// ---- encoder emission ----

/// Emit _to_json() functions for every object type in the schema
pub fn emit_encoders(schema: Schema) -> String {
  let types = collect_object_types(schema)

  types
  |> list.map(emit_single_encoder)
  |> string.join("\n\n")
}

/// One encoder function: `pub fn user_to_json(user: User) -> json.Json { ... }`
fn emit_single_encoder(obj: #(String, List(Field))) -> String {
  let #(name, fields) = obj
  let fn_name = snake_case_name(name)
  let param = fn_name

  let field_lines =
    fields
    |> list.map(fn(f) { emit_field_encoder_line(f, param) })
    |> string.join(",\n")

  "pub fn "
  <> fn_name
  <> "_to_json("
  <> param
  <> ": "
  <> name
  <> ") -> json.Json {\n  json.object([\n"
  <> field_lines
  <> ",\n  ])\n}"
}

/// One field line inside json.object([...])
fn emit_field_encoder_line(field: Field, param: String) -> String {
  let accessor = param <> "." <> field.gleam_name
  let encoder = encoder_for_field(field, accessor)
  "    #(\"" <> field.json_key <> "\", " <> encoder <> ")"
}

/// Figure out the right json.xxx call for a field
fn encoder_for_field(field: Field, accessor: String) -> String {
  case field.optional, field.schema {
    // optional + nullable — collapse to single json.nullable
    True, SNullable(inner) ->
      "json.nullable(" <> accessor <> ", " <> encoder_fn(inner) <> ")"
    // just optional
    True, other ->
      "json.nullable(" <> accessor <> ", " <> encoder_fn(other) <> ")"
    // nullable but always present
    False, SNullable(inner) ->
      "json.nullable(" <> accessor <> ", " <> encoder_fn(inner) <> ")"
    // normal field
    False, other -> encoder_expr(other, accessor)
  }
}

/// Direct encoder expression for a value: `json.string(value.name)`
fn encoder_expr(schema: Schema, accessor: String) -> String {
  case schema {
    SString -> "json.string(" <> accessor <> ")"
    SInt -> "json.int(" <> accessor <> ")"
    SFloat -> "json.float(" <> accessor <> ")"
    SBool -> "json.bool(" <> accessor <> ")"
    SDynamic -> "json.null()"
    SList(inner) ->
      "json.array(" <> accessor <> ", " <> encoder_fn(inner) <> ")"
    SObject(name, _) -> snake_case_name(name) <> "_to_json(" <> accessor <> ")"
    // shouldn't hit this normally since nullable is handled above
    SNullable(inner) ->
      "json.nullable(" <> accessor <> ", " <> encoder_fn(inner) <> ")"
  }
}

/// The function reference to pass to json.array / json.nullable
/// e.g. `json.string` or `item_to_json`
fn encoder_fn(schema: Schema) -> String {
  case schema {
    SString -> "json.string"
    SInt -> "json.int"
    SFloat -> "json.float"
    SBool -> "json.bool"
    SDynamic -> "fn(_) { json.null() }"
    SObject(name, _) -> snake_case_name(name) <> "_to_json"
    SList(_) ->
      "fn(items) { json.array(items, "
      <> encoder_fn_for_list_inner(schema)
      <> ") }"
    SNullable(inner) ->
      "fn(v) { json.nullable(v, " <> encoder_fn(inner) <> ") }"
  }
}

/// helper for nested lists
fn encoder_fn_for_list_inner(schema: Schema) -> String {
  case schema {
    SList(inner) -> encoder_fn(inner)
    _ -> encoder_fn(schema)
  }
}

// ---- unified module output ----

/// Options for controlling what gets emitted
pub type EmitOptions {
  EmitOptions(decoders: Bool, encoders: Bool)
}

/// default: emit everything
pub fn default_options() -> EmitOptions {
  EmitOptions(decoders: True, encoders: True)
}

/// Put it all together: imports + types + decoders + encoders
/// This is the main entry point for generating a complete module string.
pub fn emit_module(schema: Schema, options: EmitOptions) -> String {
  let needs_option = uses_option(schema)
  let needs_dynamic = uses_dynamic(schema)
  let has_objects = collect_object_types(schema) != []

  // figure out which imports we need
  let imports =
    build_module_imports(
      needs_option,
      needs_dynamic,
      options.decoders && has_objects,
      options.encoders && has_objects,
    )

  // build each section
  let types = emit_types_raw(schema)
  let decoders = case options.decoders && has_objects {
    True -> emit_decoders(schema)
    False -> ""
  }
  let encoders = case options.encoders && has_objects {
    True -> emit_encoders(schema)
    False -> ""
  }

  // join non-empty sections with double newlines
  [imports, types, decoders, encoders]
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
  |> string.append("\n")
}

/// Emit just type defs without their own imports (for use in emit_module)
fn emit_types_raw(schema: Schema) -> String {
  let types = collect_object_types(schema)
  types
  |> list.map(emit_single_type)
  |> string.join("\n\n")
}

/// Build all the imports needed for a complete module
fn build_module_imports(
  needs_option: Bool,
  needs_dynamic: Bool,
  needs_decode: Bool,
  needs_json: Bool,
) -> String {
  let imports = []
  let imports = case needs_json {
    True -> ["import gleam/json", ..imports]
    False -> imports
  }
  let imports = case needs_option {
    True -> ["import gleam/option.{type Option}", ..imports]
    False -> imports
  }
  let imports = case needs_dynamic {
    True -> ["import gleam/dynamic.{type Dynamic}", ..imports]
    False -> imports
  }
  let imports = case needs_decode {
    True -> ["import gleam/dynamic/decode", ..imports]
    False -> imports
  }
  imports
  |> list.sort(string.compare)
  |> string.join("\n")
}
