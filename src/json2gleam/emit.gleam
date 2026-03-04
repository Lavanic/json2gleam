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
