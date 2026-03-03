// Code emitter
//
// Right now this just handles type definitions.

import gleam/list
import gleam/string
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
