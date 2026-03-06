// Code emitter
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import gleam/string_tree
import json2gleam/schema.{
  type Field, type Schema, Field, SBool, SDynamic, SFloat, SInt, SList,
  SNullable, SObject, SString,
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
        |> list.map(fn(f) {
          let hint = field_type_hint(f)
          "    " <> f.gleam_name <> ": " <> type_string(f) <> "," <> hint
        })
        |> string.join("\n")

      "pub type "
      <> name
      <> " {\n  "
      <> name
      <> "(\n"
      <> field_lines
      <> "\n  )\n}"
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

/// Detect common patterns in field names and return a hint comment.
fn field_type_hint(field: Field) -> String {
  // Float fields get a hint about JSON int/float ambiguity
  case field.schema {
    SFloat | SNullable(SFloat) ->
      "  // JSON number — could be Int depending on your data"
    SString | SNullable(SString) ->
      detect_hint(string.lowercase(field.json_key))
    _ -> ""
  }
}

/// Check the field key against known patterns and return a hint comment
fn detect_hint(key: String) -> String {
  case is_datetime_key(key) {
    True -> "  // ISO 8601 datetime"
    False ->
      case is_id_key(key) {
        True -> "  // identifier"
        False ->
          case is_url_key(key) {
            True -> "  // URL"
            False ->
              case is_email_key(key) {
                True -> "  // email address"
                False -> ""
              }
          }
      }
  }
}

fn is_datetime_key(key: String) -> Bool {
  case key {
    "created_at"
    | "updated_at"
    | "deleted_at"
    | "expires_at"
    | "published_at"
    | "start_date"
    | "end_date"
    | "date"
    | "timestamp"
    | "due_date"
    | "birth_date"
    | "birthday" -> True
    _ -> string.ends_with(key, "_at") || string.ends_with(key, "_date")
  }
}

fn is_id_key(key: String) -> Bool {
  case key {
    "id" | "uuid" | "guid" -> True
    _ -> string.ends_with(key, "_id") || string.ends_with(key, "_uuid")
  }
}

fn is_url_key(key: String) -> Bool {
  case key {
    "url" | "href" | "uri" | "homepage" | "website" -> True
    _ ->
      string.ends_with(key, "_url")
      || string.ends_with(key, "_uri")
      || string.ends_with(key, "_href")
  }
}

fn is_email_key(key: String) -> Bool {
  case key {
    "email" -> True
    _ -> string.ends_with(key, "_email")
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

/// Walk the schema and collect all (name, fields) pairs for objects.
/// Root type comes first, then nested types after.
/// Dedupes by name so identical types arent emitted twice
fn collect_object_types(schema: Schema) -> List(#(String, List(Field))) {
  let all = collect_from_schema(schema)
  dedup_collected(all, dict.new(), [])
}

/// Keep only the first occurrence of each type name
fn dedup_collected(
  types: List(#(String, List(Field))),
  seen: dict.Dict(String, Nil),
  acc: List(#(String, List(Field))),
) -> List(#(String, List(Field))) {
  case types {
    [] -> list.reverse(acc)
    [#(name, fields), ..rest] ->
      case dict.has_key(seen, name) {
        True -> dedup_collected(rest, seen, acc)
        False ->
          dedup_collected(rest, dict.insert(seen, name, Nil), [
            #(name, fields),
            ..acc
          ])
      }
  }
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
  let constructor = case fields {
    [] -> name
    _ -> {
      let field_shorthand =
        fields
        |> list.map(fn(f) { f.gleam_name <> ":" })
        |> string.join(", ")
      name <> "(" <> field_shorthand <> ")"
    }
  }

  st
  |> string_tree.append("  decode.success(" <> constructor <> ")\n}")
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

/// turn "UserProfile" into "user_profile" for function names.
/// Handles acronyms correctly: "APIResponse" → "api_response"
fn snake_case_name(pascal_name: String) -> String {
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
        // First char: never insert underscore
        True, True -> do_snake_case(rest, [c, ..acc], False)
        // Uppercase after something: check if we need an underscore
        True, False -> {
          case acc, rest {
            // Previous char was lowercase → boundary: "user" + "P" → "user_P"
            [prev, ..], _ if prev != "_" -> {
              case is_uppercase(prev) {
                False -> do_snake_case(rest, [c, "_", ..acc], False)
                // Previous was also uppercase: check next char
                True ->
                  case rest {
                    // Next is lowercase → acronym end: "API" + "R(esponse)" → "API_R"
                    [next, ..] ->
                      case is_uppercase(next) {
                        False -> do_snake_case(rest, [c, "_", ..acc], False)
                        True -> do_snake_case(rest, [c, ..acc], False)
                      }
                    // No next char, just append
                    [] -> do_snake_case(rest, [c, ..acc], False)
                  }
              }
            }
            _, _ -> do_snake_case(rest, [c, ..acc], False)
          }
        }
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

/// Make sure a function parameter name doesn't collide with Gleam reserved words
fn sanitize_param(name: String) -> String {
  case name {
    "as"
    | "assert"
    | "auto"
    | "case"
    | "const"
    | "delegate"
    | "derive"
    | "echo"
    | "else"
    | "fn"
    | "if"
    | "implement"
    | "import"
    | "let"
    | "macro"
    | "opaque"
    | "panic"
    | "pub"
    | "test"
    | "todo"
    | "type"
    | "use" -> name <> "_val"
    _ -> name
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
  let param = sanitize_param(fn_name)

  let field_lines =
    fields
    |> list.map(fn(f) { emit_field_encoder_line(f, param) })
    |> string.join(",\n")

  // Empty objects have no fields to access, so prefix the param with _
  // to mark it as unused and satisfy the Gleam compiler
  let #(body, param_prefix) = case field_lines {
    "" -> #("  json.object([])\n}", "_")
    _ -> #("  json.object([\n" <> field_lines <> ",\n  ])\n}", "")
  }

  "pub fn "
  <> fn_name
  <> "_to_json("
  <> param_prefix
  <> param
  <> ": "
  <> name
  <> ") -> json.Json {\n"
  <> body
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
    SDynamic -> "json.null()  // Dynamic values cannot be re-encoded; emitted as null"
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
  encoder_fn_depth(schema, 0)
}

fn encoder_fn_depth(schema: Schema, depth: Int) -> String {
  let var = lambda_var(depth)
  case schema {
    SString -> "json.string"
    SInt -> "json.int"
    SFloat -> "json.float"
    SBool -> "json.bool"
    SDynamic -> "fn(_) { json.null() }  // Dynamic values cannot be re-encoded"
    SObject(name, _) -> snake_case_name(name) <> "_to_json"
    SList(inner) ->
      "fn("
      <> var
      <> ") { json.array("
      <> var
      <> ", "
      <> encoder_fn_depth(inner, depth + 1)
      <> ") }"
    SNullable(inner) ->
      "fn("
      <> var
      <> ") { json.nullable("
      <> var
      <> ", "
      <> encoder_fn_depth(inner, depth + 1)
      <> ") }"
  }
}

/// Distinct variable names for nested lambdas to avoid shadowing
fn lambda_var(depth: Int) -> String {
  case depth {
    0 -> "items"
    1 -> "inner"
    _ -> "v" <> int.to_string(depth)
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
  // dedupes the type names before emitting to avoid duplicate definitions
  // when two nested objects at different levels share the same name
  let schema = deduplicate_type_names(schema)
  case schema {
    // top-level non-object schemas get a comment + type alias + decoder
    SString | SInt | SFloat | SBool | SDynamic | SNullable(_) | SList(_) ->
      emit_toplevel_non_object(schema, options)
    // Normal object-rooted schemas get the full treatment
    SObject(_, _) -> emit_object_module(schema, options)
  }
}

/// Emit a module for a top-level non-object schema (e.g. a bare array or primitive).
/// Generates a comment explaining the shape, a type alias, and a decoder.
fn emit_toplevel_non_object(schema: Schema, options: EmitOptions) -> String {
  let type_str = schema_type_string(schema)
  let has_objects = collect_object_types(schema) != []
  let needs_option = uses_option(schema)
  let needs_dynamic = uses_dynamic(schema)

  let imports =
    build_module_imports(
      needs_option,
      needs_dynamic,
      options.decoders,
      options.encoders && has_objects,
    )

  let comment = "/// The top-level JSON value is: " <> type_str

  // Nested object types (e.g. List(Item) needs the Item type)
  let types = emit_types_raw(schema)

  let decoder = case options.decoders {
    True -> {
      let dec = decoder_for_schema(schema)
      "/// Decoder for the top-level value\npub fn decoder() -> decode.Decoder("
      <> type_str
      <> ") {\n  "
      <> dec
      <> "\n}"
    }
    False -> ""
  }

  // Nested object decoders
  let nested_decoders = case options.decoders && has_objects {
    True -> emit_decoders(schema)
    False -> ""
  }

  // Nested object encoders
  let nested_encoders = case options.encoders && has_objects {
    True -> emit_encoders(schema)
    False -> ""
  }

  [imports, comment, types, decoder, nested_decoders, nested_encoders]
  |> list.filter(fn(s) { s != "" })
  |> string.join("\n\n")
  |> string.append("\n")
}

/// emit module for a normal object-rooted schema
fn emit_object_module(schema: Schema, options: EmitOptions) -> String {
  let needs_option = uses_option(schema)
  let needs_dynamic = uses_dynamic(schema)
  let has_objects = collect_object_types(schema) != []

  let imports =
    build_module_imports(
      needs_option,
      needs_dynamic,
      options.decoders && has_objects,
      options.encoders && has_objects,
    )

  let types = emit_types_raw(schema)
  let decoders = case options.decoders && has_objects {
    True -> emit_decoders(schema)
    False -> ""
  }
  let encoders = case options.encoders && has_objects {
    True -> emit_encoders(schema)
    False -> ""
  }

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

// deduping

/// Walk the schema tree top-down and rename SObjects that collide
/// with an already-seen type name but have a different field structure.
/// E.g. two nested objects both named "Data" with different fields
/// become "Data" and "Data2".
fn deduplicate_type_names(schema: Schema) -> Schema {
  let #(result, _) = dedup_schema(schema, dict.new())
  result
}

fn dedup_schema(
  schema: Schema,
  seen: dict.Dict(String, List(Field)),
) -> #(Schema, dict.Dict(String, List(Field))) {
  case schema {
    SObject(name, fields) -> {
      // Pick a unique name for this object type
      let #(actual_name, seen) = case dict.get(seen, name) {
        // First time seeing this name — claim it
        Error(_) -> #(name, dict.insert(seen, name, fields))
        Ok(existing_fields) ->
          case existing_fields == fields {
            // Same structure just reuse the name
            True -> #(name, seen)
            // Different structure so find a unique suffix
            False -> {
              let new_name = find_unique_type_name(name, seen, 2)
              #(new_name, dict.insert(seen, new_name, fields))
            }
          }
      }
      // Recurse into child fields
      let #(new_fields, seen) = dedup_fields(fields, seen)
      #(SObject(actual_name, new_fields), seen)
    }
    SList(inner) -> {
      let #(new_inner, seen) = dedup_schema(inner, seen)
      #(SList(new_inner), seen)
    }
    SNullable(inner) -> {
      let #(new_inner, seen) = dedup_schema(inner, seen)
      #(SNullable(new_inner), seen)
    }
    _ -> #(schema, seen)
  }
}

fn dedup_fields(
  fields: List(Field),
  seen: dict.Dict(String, List(Field)),
) -> #(List(Field), dict.Dict(String, List(Field))) {
  let #(reversed, seen) =
    list.fold(fields, #([], seen), fn(acc, field) {
      let #(done, seen) = acc
      let #(new_schema, seen) = dedup_schema(field.schema, seen)
      #([Field(..field, schema: new_schema), ..done], seen)
    })
  #(list.reverse(reversed), seen)
}

/// Find a name like "Data2", "Data3", etc. that isn't already taken
fn find_unique_type_name(
  base: String,
  seen: dict.Dict(String, List(Field)),
  n: Int,
) -> String {
  let candidate = base <> int.to_string(n)
  case dict.has_key(seen, candidate) {
    True -> find_unique_type_name(base, seen, n + 1)
    False -> candidate
  }
}
